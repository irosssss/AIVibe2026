// AIVibe/Core/Agents/AgentOrchestrator.swift
// Оркестратор пайплайна: скан → геометрия → дизайн → (retry при коллизиях).

import Foundation
import RoomPlan
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
    /// Живой партнёрский каталог (B4): артикулы в промпт LLM + резолвер
    /// (габариты/цена/USDZ). nil = работаем без каталога (как раньше).
    private let catalogClient: PartnerCatalogClient?
    private let logger = Logger(label: "ru.aivibe.orchestrator")

    public init(
        scanAgent: any ScanAgentProtocol,
        analyzerAgent: any AnalyzerAgentProtocol,
        aiRouter: AIProviderRouter,
        promptBuilder: any PromptBuilding = PromptBuilder(),
        parser: any DesignResponseParsing = DesignResponseParser(),
        collisionDetector: any CollisionDetecting = CollisionDetector(),
        analytics: any AnalyticsLogging = NoopAnalytics(),
        catalogClient: PartnerCatalogClient? = nil
    ) {
        self.scanAgent = scanAgent
        self.analyzerAgent = analyzerAgent
        self.aiRouter = aiRouter
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.collisionDetector = collisionDetector
        self.analytics = analytics
        self.catalogClient = catalogClient
    }

    // MARK: - Главный пайплайн

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

    // MARK: - Генерация дизайна из готовой геометрии

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
            var refined = try parser.parse(response: response, providerName: response.providerName)
            refined = await enrichWithCatalog(refined)

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

        // B4: блок каталога фабрик — LLM выбирает предметы по реальным
        // артикулам. Запрашивается один раз на все попытки; сбой каталога
        // не валит генерацию (работаем без артикулов, как раньше).
        let catalogBlock = await fetchCatalogPromptBlock(preferences: preferences)

        for attempt in 1...maxAttempts {
            var prompt: AIPrompt
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
            if let catalogBlock {
                prompt = AIPrompt(
                    messages: prompt.messages + [ChatMessage(role: .user, content: catalogBlock)],
                    temperature: prompt.temperature,
                    maxTokens: prompt.maxTokens
                )
            }

            do {
                let response = try await aiRouter.complete(prompt: prompt)
                var plan = try parser.parse(response: response, providerName: response.providerName)
                plan = await enrichWithCatalog(plan)
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

    // MARK: - B4: партнёрский каталог в пайплайне

    /// Подборка каталога для промпта: LLM использует реальные артикулы.
    /// Любой сбой (нет сети/конфига/пустой каталог) → nil, генерация идёт без каталога.
    private func fetchCatalogPromptBlock(preferences: UserDesignPreferences) async -> String? {
        guard let catalogClient else { return nil }
        let products = (try? await catalogClient.search(
            "мебель для комнаты",
            preferences.style.rawValue,
            preferences.budgetMax
        )) ?? []
        guard !products.isEmpty else { return nil }

        var lines = [
            "Каталог фабрик-партнёров (доступная мебель).",
            "В поле \"article\" используй ТОЛЬКО артикулы из этого списка.",
            "Поле \"usdz_url\" оставляй пустым.",
            "Если подходящего предмета в списке нет — оставь article пустым."
        ]
        for product in products {
            var line = "- \(product.article) · \(product.category) · \(product.name)"
            if let w = product.widthCm, let d = product.depthCm, let h = product.heightCm {
                line += " · \(w)×\(d)×\(h) см"
            }
            if let price = product.price {
                line += " · \(price) ₽"
            }
            lines.append(line)
        }
        logger.info("B4: каталог в промпте — \(products.count) позиций")
        return lines.joined(separator: "\n")
    }

    /// Резолвер артикулов (B3→B4): для каждого предмета с артикулом подтягивает
    /// из каталога реальные габариты, цену и USDZ. Не найден/сбой → предмет
    /// остаётся как есть (bundle-фолбэк по типу сработает в USDZLoader).
    private func enrichWithCatalog(_ plan: RoomDesignPlan) async -> RoomDesignPlan {
        guard let catalogClient else { return plan }
        let articles = plan.items.filter { !$0.article.isEmpty }
        guard !articles.isEmpty else { return plan }

        // Резолвим уникальные артикулы параллельно.
        let uniqueArticles = Set(articles.map(\.article))
        var resolved: [String: PartnerProduct] = [:]
        await withTaskGroup(of: (String, PartnerProduct?).self) { group in
            for article in uniqueArticles {
                group.addTask {
                    (article, try? await catalogClient.resolve(article) ?? nil)
                }
            }
            for await (article, product) in group {
                if let product { resolved[article] = product }
            }
        }
        guard !resolved.isEmpty else { return plan }

        let enrichedItems = plan.items.map { item -> FurnitureItem in
            guard let product = resolved[item.article] else { return item }

            // Габариты каталога (см → м); нет габаритов — оставляем размер LLM.
            var size = item.size
            if let w = product.widthCm, let d = product.depthCm, let h = product.heightCm {
                size = SIMD3<Float>(Float(w) / 100, Float(h) / 100, Float(d) / 100)
            }

            return FurnitureItem(
                id: item.id,
                itemType: item.itemType,
                brand: product.name,
                article: item.article,
                position: item.position,
                rotation: item.rotation,
                size: size,
                usdzURL: usdzSource(for: product),
                price: product.price
            )
        }

        logger.info("B4: резолвер обогатил \(resolved.count) из \(uniqueArticles.count) артикулов")
        return RoomDesignPlan(
            id: plan.id,
            items: enrichedItems,
            explanation: plan.explanation,
            confidence: plan.confidence,
            generatedAt: plan.generatedAt,
            providerName: plan.providerName
        )
    }

    /// Источник USDZ для предмета каталога: модель из бандла (мгновенно,
    /// офлайн) имеет приоритет над сетевой ссылкой — бакет aivibe-models
    /// наполнится конвейером B1 позже.
    private func usdzSource(for product: PartnerProduct) -> String {
        if let bundled = PartnerCatalogStub.item(article: product.article) {
            return bundled.usdzFile
        }
        return product.usdzURLString
    }

    private func buildCollisionDescription(report: CollisionReport) -> String {
        var parts: [String] = []
        if !report.collidingPairs.isEmpty {
            let pairs = report.collidingPairs.map { "\($0.first.itemType) и \($0.second.itemType)" }
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
        // Полный live-роутер (Backend → YandexGPT → GigaChat → CoreML).
        // Раньше здесь был AIProviderRouter(providers: []) — генерация дизайна
        // на устройстве была обречена падать.
        let router = AppDependencies.prepareLiveRouter()
        let analytics = AppMetricaAnalytics()
        return AgentOrchestrator(
            scanAgent: ScanAgent(),
            analyzerAgent: AnalyzerAgent(analytics: analytics),
            aiRouter: router,
            analytics: analytics,
            catalogClient: .liveValue
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
