// AIVibe/Core/Agents/AgentOrchestrator.swift
// Оркестратор пайплайна: скан → геометрия → дизайн → (retry при коллизиях).

import Foundation
#if canImport(RoomPlan)
import RoomPlan
#endif
import Logging
import ComposableArchitecture

// MARK: - Ошибки оркестратора

public enum AgentError: LocalizedError, Sendable {
    case scanQualityInsufficient(issues: [ScanIssue])
    case designGenerationFailed(underlying: Error)
    case allRetriesExhausted(attempts: Int)
    case refinementFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .scanQualityInsufficient(let issues):
            return "Качество скана недостаточно: \(issues.count) проблем"
        case .designGenerationFailed(let error):
            return "Генерация дизайна провалилась: \(error.localizedDescription)"
        case .allRetriesExhausted(let count):
            return "Исчерпано \(count) попыток генерации дизайна"
        case .refinementFailed(let error):
            return "Уточнение дизайна провалилось: \(error.localizedDescription)"
        }
    }
}

// MARK: - AgentOrchestrator

public actor AgentOrchestrator {

    private let scanAgent: any ScanAgentProtocol
    private let analyzerAgent: any AnalyzerAgentProtocol
    private let aiRouter: AIProviderRouter
    private let promptBuilder: any PromptBuilding
    private let parser: any DesignResponseParsing
    private let collisionDetector: any CollisionDetecting
    private let analytics: any AnalyticsLogging
    private let logger = Logger(label: "ru.aivibe.orchestrator")

    public init(
        scanAgent: any ScanAgentProtocol,
        analyzerAgent: any AnalyzerAgentProtocol,
        aiRouter: AIProviderRouter,
        promptBuilder: any PromptBuilding = PromptBuilder(),
        parser: any DesignResponseParsing = DesignResponseParser(),
        collisionDetector: any CollisionDetecting = CollisionDetector(),
        analytics: any AnalyticsLogging = NoopAnalytics()
    ) {
        self.scanAgent = scanAgent
        self.analyzerAgent = analyzerAgent
        self.aiRouter = aiRouter
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.collisionDetector = collisionDetector
        self.analytics = analytics
    }

    // MARK: - Главный пайплайн (требует RoomPlan)

    #if canImport(RoomPlan)

    public func runDesignPipeline(
        room capturedRoom: CapturedRoom,
        preferences: UserDesignPreferences
    ) async throws -> RoomDesignPlan {
        let pipelineStart = Date()
        analytics.log(event: "design_pipeline_started", params: [:])

        // 1. Проверка качества скана
        let quality = await scanAgent.check(capturedRoom)
        guard quality.canProceed else {
            logger.warning("Пайплайн отклонён: quality.score=\(quality.score)")
            analytics.log(event: "pipeline_scan_rejected", params: [
                "score": quality.score,
                "issues": quality.issues.count
            ])
            throw AgentError.scanQualityInsufficient(issues: quality.issues)
        }

        // 2. Извлечение геометрии
        let geometry = try await analyzerAgent.extract(capturedRoom)

        // 3. Генерация дизайна с retry при коллизиях
        let plan = try await generateWithRetry(
            geometry: geometry,
            preferences: preferences,
            maxAttempts: 2
        )

        let durationMs = Int(Date().timeIntervalSince(pipelineStart) * 1000)
        analytics.log(event: "design_pipeline_completed", params: [
            "duration_ms": durationMs,
            "provider": plan.providerName,
            "items_count": plan.items.count,
            "confidence": plan.confidence
        ])

        logger.info("Пайплайн завершён за \(durationMs) мс, \(plan.items.count) предметов")
        return plan
    }

    #endif // canImport(RoomPlan)

    // MARK: - Генерация дизайна из готовой геометрии (не требует RoomPlan)

    public func generateDesign(
        geometry: RoomGeometry,
        preferences: UserDesignPreferences
    ) async throws -> RoomDesignPlan {
        let pipelineStart = Date()
        analytics.log(event: "design_generation_started", params: [:])

        let plan = try await generateWithRetry(
            geometry: geometry,
            preferences: preferences,
            maxAttempts: 2
        )

        let durationMs = Int(Date().timeIntervalSince(pipelineStart) * 1000)
        analytics.log(event: "design_generation_completed", params: [
            "duration_ms": durationMs,
            "provider": plan.providerName,
            "items_count": plan.items.count
        ])
        return plan
    }

    // MARK: - Уточнение дизайна (не требует RoomPlan)

    public func refine(
        plan: RoomDesignPlan,
        room: RoomGeometry,
        feedback: UserFeedback
    ) async throws -> RoomDesignPlan {
        let prompt = promptBuilder.buildRefinePrompt(currentDesign: plan, feedback: feedback)

        do {
            let response = try await aiRouter.complete(prompt: prompt)
            let refined = try parser.parse(response: response, providerName: response.providerName)

            let report = collisionDetector.check(plan: refined, room: room)
            if !report.isClean {
                logger.warning("Refinement: обнаружены коллизии (\(report.collidingPairs.count) пар)")
            }

            analytics.log(event: "design_refined", params: [
                "items_count": refined.items.count,
                "confidence": refined.confidence
            ])
            return refined

        } catch {
            throw AgentError.refinementFailed(underlying: error)
        }
    }

    // MARK: - Retry при коллизиях

    private func generateWithRetry(
        geometry: RoomGeometry,
        preferences: UserDesignPreferences,
        maxAttempts: Int
    ) async throws -> RoomDesignPlan {
        var lastError: Error?
        var collisionInfo: String?

        for attempt in 1...maxAttempts {
            let prompt: AIPrompt
            if let info = collisionInfo {
                // Повторяем с описанием коллизий из предыдущей попытки
                prompt = promptBuilder.buildRetryPrompt(
                    geometry: geometry,
                    preferences: preferences,
                    collisionInfo: info
                )
            } else {
                prompt = promptBuilder.buildDesignPrompt(geometry: geometry, preferences: preferences)
            }

            do {
                let response = try await aiRouter.complete(prompt: prompt)
                let plan = try parser.parse(response: response, providerName: response.providerName)
                let report = collisionDetector.check(plan: plan, room: geometry)

                if report.isClean || attempt == maxAttempts {
                    if !report.isClean {
                        logger.warning("Попытка \(attempt)/\(maxAttempts): коллизии сохранились, возвращаем как есть")
                    }
                    return plan
                }

                // Формируем описание коллизий для следующей попытки
                collisionInfo = buildCollisionDescription(report: report)
                logger.info("Попытка \(attempt)/\(maxAttempts): \(report.collidingPairs.count) коллизий, retry")

            } catch {
                lastError = error
                logger.error("Попытка \(attempt)/\(maxAttempts) упала: \(error.localizedDescription)")
            }
        }

        if let error = lastError {
            throw AgentError.designGenerationFailed(underlying: error)
        }
        throw AgentError.allRetriesExhausted(attempts: maxAttempts)
    }

    private func buildCollisionDescription(report: CollisionReport) -> String {
        var parts: [String] = []
        if !report.collidingPairs.isEmpty {
            let pairs = report.collidingPairs.map { "\($0.0.itemType) и \($0.1.itemType)" }
            parts.append("Коллизии: \(pairs.joined(separator: "; "))")
        }
        if !report.itemsOutOfBounds.isEmpty {
            let types = report.itemsOutOfBounds.map { $0.itemType }
            parts.append("За пределами комнаты: \(types.joined(separator: ", "))")
        }
        if !report.blockedDoors.isEmpty {
            parts.append("Заблокировано \(report.blockedDoors.count) дверей")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - TCA Dependency

extension DependencyValues {
    public var agentOrchestrator: AgentOrchestrator {
        get { self[AgentOrchestratorKey.self] }
        set { self[AgentOrchestratorKey.self] = newValue }
    }
}

private enum AgentOrchestratorKey: DependencyKey {
    static let liveValue: AgentOrchestrator = {
        let router = AIProviderRouter(providers: [])
        let analytics = AppMetricaAnalytics()
        return AgentOrchestrator(
            scanAgent: ScanAgent(),
            analyzerAgent: AnalyzerAgent(analytics: analytics),
            aiRouter: router,
            analytics: analytics
        )
    }()

    static let testValue: AgentOrchestrator = {
        AgentOrchestrator(
            scanAgent: ScanAgent(),
            analyzerAgent: AnalyzerAgent(),
            aiRouter: AIProviderRouter(providers: [])
        )
    }()
}
