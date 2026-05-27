// AIVibe/Core/AI/Agent/AgentObservability.swift
// Blueprint §13: Observability — tracing events, metrics, 8 eval probes.
// Собирает телеметрию со всех компонентов агента: loop, tools, providers, compaction.

import Foundation
import Logging

// MARK: - Trace Event

/// Событие трассировки агента (Blueprint §13: Trace events).
public enum TraceEventType: String, Sendable, Codable {
    case sessionStart       = "session_start"
    case toolCall           = "tool_call"
    case toolResult         = "tool_result"
    case providerSwitch     = "provider_switch"
    case approvalRequest    = "approval_request"
    case approvalDecision   = "approval_decision"
    case compaction         = "compaction"
    case sessionEnd         = "session_end"
    case providerHealthCheck = "provider_health_check"
    case evalProbeStarted   = "eval_probe_started"
    case evalProbeCompleted = "eval_probe_completed"
    case evalProbeFailed    = "eval_probe_failed"
}

/// Запись трассировки.
public struct TraceRecord: Sendable, Codable, Identifiable {
    public let id: String
    public let eventType: TraceEventType
    public let timestamp: Date
    public let sessionId: String?
    public let step: Int?
    public let toolName: String?
    public let providerName: String?
    public let durationMs: Double?
    public let resultSize: Int?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        eventType: TraceEventType,
        sessionId: String? = nil,
        step: Int? = nil,
        toolName: String? = nil,
        providerName: String? = nil,
        durationMs: Double? = nil,
        resultSize: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.eventType = eventType
        self.timestamp = Date()
        self.sessionId = sessionId
        self.step = step
        self.toolName = toolName
        self.providerName = providerName
        self.durationMs = durationMs
        self.resultSize = resultSize
        self.metadata = metadata
    }

    /// Сериализация в JSON для логов.
    public func toJSON() -> String {
        var dict: [String: Any] = [
            "id": id,
            "event": eventType.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let sid = sessionId { dict["session_id"] = sid }
        if let s = step { dict["step"] = s }
        if let tn = toolName { dict["tool"] = tn }
        if let pn = providerName { dict["provider"] = pn }
        if let d = durationMs { dict["duration_ms"] = d }
        if let rs = resultSize { dict["result_size"] = rs }
        if !metadata.isEmpty { dict["meta"] = metadata }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - Observability Collector

/// Собирает trace events и метрики (Blueprint §13).
///
/// ## Метрики (Blueprint §13):
/// - `tool_call_success_rate` — цель > 95%
/// - `provider_fallback_rate` — цель < 5%
/// - `approval_acceptance_rate` — мониторинг
/// - `avg_steps_per_session` — цель < 6
/// - `compaction_frequency` — мониторинг
/// - `user_satisfaction_score` — пост-сессия опрос
public actor ObservabilityCollector {

    // MARK: - Properties

    /// Все trace-записи (in-memory, сбрасываются при необходимости).
    private var traces: [TraceRecord] = []

    /// Счётчики метрик.
    private var metrics: AgentMetrics = AgentMetrics()

    /// Логгер.
    private let logger = Logger(label: "ai.observability")

    /// Максимальное количество trace-записей (предотвращает утечку памяти).
    private let maxTraces = 1000

    // MARK: - Init

    public init() {}

    // MARK: - Trace Recording

    /// Записывает trace-событие.
    public func record(_ event: TraceRecord) {
        traces.append(event)

        // Обновляем метрики
        updateMetrics(event)

        // Логируем в JSON (Yandex Cloud Logging подхватит)
        logger.info("📊 TRACE: \(event.toJSON())")

        // Ограничиваем размер traces
        if traces.count > maxTraces {
            traces.removeFirst(traces.count - maxTraces)
        }
    }

    /// Записывает событие сессии.
    public func recordSessionStart(sessionId: String, userId: String) {
        record(TraceRecord(
            eventType: .sessionStart,
            sessionId: sessionId,
            metadata: ["user_id": userId]
        ))
    }

    /// Записывает tool call.
    public func recordToolCall(
        toolName: String,
        step: Int,
        sessionId: String,
        durationMs: Double,
        resultSize: Int,
        success: Bool,
        providerName: String? = nil
    ) {
        record(TraceRecord(
            eventType: success ? .toolResult : .toolCall,
            sessionId: sessionId,
            step: step,
            toolName: toolName,
            providerName: providerName,
            durationMs: durationMs,
            resultSize: resultSize,
            metadata: ["status": success ? "success" : "failure"]
        ))

        // Обновляем tool-specific метрики
        metrics.trackToolCall(toolName: toolName, success: success, durationMs: durationMs)
    }

    /// Записывает переключение провайдера.
    public func recordProviderSwitch(
        from: String,
        to: String,
        reason: String,
        sessionId: String?
    ) {
        record(TraceRecord(
            eventType: .providerSwitch,
            sessionId: sessionId,
            providerName: to,
            metadata: [
                "from_provider": from,
                "to_provider": to,
                "reason": reason
            ]
        ))

        metrics.trackProviderFallback()
    }

    /// Записывает compaction.
    public func recordCompaction(
        charsBefore: Int,
        charsAfter: Int,
        sessionId: String?
    ) {
        record(TraceRecord(
            eventType: .compaction,
            sessionId: sessionId,
            resultSize: charsAfter,
            metadata: [
                "chars_before": String(charsBefore),
                "chars_after": String(charsAfter),
                "savings": String(charsBefore - charsAfter)
            ]
        ))

        metrics.trackCompaction()
    }

    /// Записывает завершение сессии.
    public func recordSessionEnd(
        sessionId: String,
        totalSteps: Int,
        outcome: String,
        totalDurationMs: Double
    ) {
        record(TraceRecord(
            eventType: .sessionEnd,
            sessionId: sessionId,
            step: totalSteps,
            durationMs: totalDurationMs,
            metadata: [
                "outcome": outcome,
                "total_steps": String(totalSteps)
            ]
        ))

        metrics.trackSessionEnd(steps: totalSteps, outcome: outcome)
    }

    // MARK: - Metrics

    /// Возвращает текущий снимок метрик.
    public func snapshot() -> AgentMetrics {
        metrics
    }

    /// Сбрасывает метрики.
    public func resetMetrics() {
        metrics = AgentMetrics()
        logger.info("🔄 Метрики сброшены")
    }

    // MARK: - Private

    private func updateMetrics(_ event: TraceRecord) {
        switch event.eventType {
        case .toolResult:
            metrics.totalToolCalls += 1
        case .providerSwitch:
            metrics.totalProviderFallbacks += 1
        case .compaction:
            metrics.totalCompactions += 1
        default:
            break
        }
    }
}

// MARK: - Agent Metrics

/// Снимок метрик агента (Blueprint §13).
public struct AgentMetrics: Sendable, Codable {

    // MARK: - Counters

    /// Общее количество вызовов инструментов.
    public var totalToolCalls: Int = 0

    /// Количество успешных вызовов инструментов.
    public var successfulToolCalls: Int = 0

    /// Количество fallback-переключений провайдеров.
    public var totalProviderFallbacks: Int = 0

    /// Количество compaction-событий.
    public var totalCompactions: Int = 0

    /// Количество завершённых сессий.
    public var completedSessions: Int = 0

    /// Суммарное количество шагов всех сессий.
    public var totalStepsAcrossSessions: Int = 0

    /// Количество сессий с ошибкой.
    public var erroredSessions: Int = 0

    /// Количество сессий, достигнувших бюджета шагов.
    public var budgetDepletedSessions: Int = 0

    /// Количество approval-событий.
    public var totalApprovalRequests: Int = 0

    // MARK: - Per-Tool Stats

    /// Статистика по каждому инструменту.
    public var perToolStats: [String: ToolStats] = [:]

    // MARK: - Computed Metrics

    /// Успешность вызовов инструментов (цель > 95%).
    public var toolCallSuccessRate: Double {
        guard totalToolCalls > 0 else { return 1.0 }
        return Double(successfulToolCalls) / Double(totalToolCalls)
    }

    /// Частота fallback-переключений провайдеров (цель < 5%).
    public var providerFallbackRate: Double {
        guard totalToolCalls > 0 else { return 0 }
        return Double(totalProviderFallbacks) / Double(totalToolCalls)
    }

    /// Среднее количество шагов на сессию (цель < 6).
    public var avgStepsPerSession: Double {
        guard completedSessions > 0 else { return 0 }
        return Double(totalStepsAcrossSessions) / Double(completedSessions)
    }

    /// Частота compaction (compactions на сессию).
    public var compactionFrequency: Double {
        guard completedSessions > 0 else { return 0 }
        return Double(totalCompactions) / Double(completedSessions)
    }

    /// Доля сессий с ошибкой.
    public var sessionErrorRate: Double {
        guard completedSessions > 0 else { return 0 }
        return Double(erroredSessions) / Double(completedSessions)
    }

    // MARK: - Mutating

    public mutating func trackToolCall(toolName: String, success: Bool, durationMs: Double) {
        totalToolCalls += 1
        if success { successfulToolCalls += 1 }
        perToolStats[toolName, default: ToolStats()].record(success: success, durationMs: durationMs)
    }

    public mutating func trackProviderFallback() {
        totalProviderFallbacks += 1
    }

    public mutating func trackCompaction() {
        totalCompactions += 1
    }

    public mutating func trackSessionEnd(steps: Int, outcome: String) {
        completedSessions += 1
        totalStepsAcrossSessions += steps
        if outcome == "error" || outcome == "all_providers_exhausted" {
            erroredSessions += 1
        }
        if outcome == "step_budget_reached" {
            budgetDepletedSessions += 1
        }
    }
}

// MARK: - Tool Stats

/// Статистика по одному инструменту.
public struct ToolStats: Sendable, Codable {
    public var callCount: Int = 0
    public var successCount: Int = 0
    public var failureCount: Int = 0
    public var totalDurationMs: Double = 0
    public var minDurationMs: Double = .infinity
    public var maxDurationMs: Double = 0

    public var successRate: Double {
        guard callCount > 0 else { return 1.0 }
        return Double(successCount) / Double(callCount)
    }

    public var avgDurationMs: Double {
        guard callCount > 0 else { return 0 }
        return totalDurationMs / Double(callCount)
    }

    public mutating func record(success: Bool, durationMs: Double) {
        callCount += 1
        if success { successCount += 1 } else { failureCount += 1 }
        totalDurationMs += durationMs
        if durationMs < minDurationMs { minDurationMs = durationMs }
        if durationMs > maxDurationMs { maxDurationMs = durationMs }
    }
}

// MARK: - Eval Probe

/// Тестовый зонд для проверки поведения агента (Blueprint §13: 8 eval probes).
public struct EvalProbe: Sendable, Identifiable {
    /// Уникальный идентификатор зонда.
    public let id: String

    /// Название тестового сценария.
    public let name: String

    /// Описание проверяемого поведения.
    public let description: String

    /// Входной запрос.
    public let input: UserRequest

    /// Ожидаемый результат.
    public let expectedOutcome: ExpectedOutcome

    /// Ожидаемые вызванные инструменты.
    public let expectedTools: [String]

    /// Является ли проба критичной для запуска.
    public let isLaunchGate: Bool

    public enum ExpectedOutcome: String, Sendable {
        case completed
        case approvalRequired
        case error
        case noAction
        case stepBudgetReached
    }

    public init(
        id: String,
        name: String,
        description: String,
        input: UserRequest,
        expectedOutcome: ExpectedOutcome,
        expectedTools: [String] = [],
        isLaunchGate: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.input = input
        self.expectedOutcome = expectedOutcome
        self.expectedTools = expectedTools
        self.isLaunchGate = isLaunchGate
    }

    /// 8 стандартных eval probes (Blueprint §13).
    public static let standardProbes: [EvalProbe] = [
        // 1. Пустая комната → предложить стиль и базовую мебель
        EvalProbe(
            id: "probe_01_empty_room",
            name: "Пустая комната 15м²",
            description: "Агент должен предложить стиль и базовую мебель для пустой комнаты",
            input: UserRequest(
                inputType: .lidarScan,
                message: "У меня пустая комната 15м², нужен дизайн",
                roomId: "room_empty_15m2"
            ),
            expectedOutcome: .completed,
            expectedTools: ["analyze_room_scan", "recommend_style", "search_marketplace_furniture"],
            isLaunchGate: true
        ),

        // 2. Бюджет 50 000 ₽ → бюджетные варианты
        EvalProbe(
            id: "probe_02_tight_budget",
            name: "Бюджет 50 000 ₽ на комнату",
            description: "Агент должен предложить бюджетные варианты в рамках 50 000 ₽",
            input: UserRequest(
                inputType: .textPrompt,
                message: "Нужна мебель в гостиную 18м². Бюджет 50 000 ₽",
                budgetRange: (min: 0, max: 50_000)
            ),
            expectedOutcome: .completed,
            expectedTools: ["search_marketplace_furniture", "draft_shopping_list"],
            isLaunchGate: true
        ),

        // 3. YandexGPT недоступен → GigaChat (Circuit Breaker)
        EvalProbe(
            id: "probe_03_provider_fallback",
            name: "YandexGPT недоступен",
            description: "Агент должен переключиться на GigaChat при недоступности YandexGPT",
            input: UserRequest(
                message: "Какой стиль выбрать для спальни?"
            ),
            expectedOutcome: .completed,
            isLaunchGate: true
        ),

        // 4. GigaChat тоже недоступен → CoreML
        EvalProbe(
            id: "probe_04_coreml_fallback",
            name: "Все облачные провайдеры недоступны",
            description: "Агент должен переключиться на CoreML при недоступности всех облачных провайдеров",
            input: UserRequest(
                message: "Посоветуй цвет стен для гостиной"
            ),
            expectedOutcome: .completed,
            isLaunchGate: true
        ),

        // 5. Товар не в наличии → альтернатива
        EvalProbe(
            id: "probe_05_out_of_stock",
            name: "Товар не в наличии",
            description: "Агент должен предложить альтернативу, если товар не в наличии",
            input: UserRequest(
                message: "Подбери диван до 30 000 ₽. Если товара нет — предложи аналог",
                budgetRange: (min: 0, max: 30_000)
            ),
            expectedOutcome: .completed,
            expectedTools: ["search_marketplace_furniture"],
            isLaunchGate: true
        ),

        // 6. Комната без окон → решения по освещению
        EvalProbe(
            id: "probe_06_no_windows",
            name: "Комната без окон",
            description: "Агент должен предложить решения по освещению для комнаты без окон",
            input: UserRequest(
                inputType: .lidarScan,
                message: "Комната 12м² без окон (гардеробная). Как осветить?",
                roomId: "room_no_windows"
            ),
            expectedOutcome: .completed,
            expectedTools: ["analyze_room_scan", "recommend_style"],
            isLaunchGate: false
        ),

        // 7. «Не нравится» → альтернативный стиль
        EvalProbe(
            id: "probe_07_alternative_style",
            name: "Пользователь говорит «не нравится»",
            description: "Агент должен предложить альтернативный стиль при отказе от первого",
            input: UserRequest(
                message: "Ты предложил скандинавский стиль, но мне он не нравится. Что ещё?"
            ),
            expectedOutcome: .completed,
            expectedTools: ["recommend_style"],
            isLaunchGate: false
        ),

        // 8. Несущая стена мешает → предупреждение
        EvalProbe(
            id: "probe_08_load_bearing_wall",
            name: "Несущая стена мешает расстановке",
            description: "Агент должен предупредить, если несущая стена мешает плану расстановки",
            input: UserRequest(
                inputType: .lidarScan,
                message: "Расставь мебель в комнате 20м² с несущей стеной по центру",
                roomId: "room_load_bearing"
            ),
            expectedOutcome: .completed,
            expectedTools: ["analyze_room_scan", "generate_arrangement_plan"],
            isLaunchGate: true
        )
    ]
}

// MARK: - Eval Probe Runner

/// Запускает eval probes и оценивает результаты (Blueprint §13: Launch gates).
public actor EvalProbeRunner {

    /// Коллектор телеметрии.
    private let collector: ObservabilityCollector

    /// Логгер.
    private let logger = Logger(label: "ai.eval-runner")

    /// Результаты запусков.
    private var results: [String: EvalProbeResult] = [:]

    public init(collector: ObservabilityCollector = ObservabilityCollector()) {
        self.collector = collector
    }

    /// Запускает все eval probes (Blueprint §13: 8 probes).
    /// - Parameter runProbe: Асинхронное замыкание, выполняющее один probe (внедрение AgentLoop).
    /// - Returns: Словарь результатов probe_id → результат.
    public func runAllProbes(
        _ runProbe: @Sendable (EvalProbe) async -> EvalProbeResult
    ) async -> [String: EvalProbeResult] {
        logger.info("🧪 Запуск \(EvalProbe.standardProbes.count) eval probes...")

        results.removeAll()

        for probe in EvalProbe.standardProbes {
            logger.info("🧪 Probe: \(probe.name) (\(probe.id))")

            let result = await runProbe(probe)
            results[probe.id] = result

            // Логируем результат
            await collector.record(TraceRecord(
                eventType: result.passed ? .evalProbeCompleted : .evalProbeFailed,
                toolName: probe.id,
                metadata: [
                    "name": probe.name,
                    "passed": result.passed ? "true" : "false",
                    "outcome": result.actualOutcome.rawValue,
                    "expected": result.expectedOutcome.rawValue,
                    "duration_ms": String(format: "%.2f", result.durationMs)
                ]
            ))

            logger.info("   \(result.passed ? "✅" : "❌") \(probe.name): \(result.summary)")
        }

        let passedCount = results.values.filter(\.passed).count
        let totalCount = results.count
        logger.info("🧪 Результаты: \(passedCount)/\(totalCount) пройдено")

        return results
    }

    /// Проверяет launch gates (Blueprint §13: Launch gates checklist).
    /// - Returns: `true` если все launch-gate пробы пройдены.
    public func allLaunchGatesPassed() -> Bool {
        let launchGateResults = results.filter { probeId, _ in
            EvalProbe.standardProbes.first(where: { $0.id == probeId })?.isLaunchGate ?? false
        }
        return launchGateResults.values.allSatisfy(\.passed)
    }

    /// Возвращает сводку результатов.
    public func summary() -> EvalSummary {
        let allResults = results
        let launchGates = allResults.filter { id, _ in
            EvalProbe.standardProbes.first(where: { $0.id == id })?.isLaunchGate ?? false
        }

        return EvalSummary(
            totalProbes: allResults.count,
            passedProbes: allResults.values.filter(\.passed).count,
            failedProbes: allResults.values.filter { !$0.passed }.count,
            launchGatesTotal: launchGates.count,
            launchGatesPassed: launchGates.values.filter(\.passed).count,
            launchGatesFailed: launchGates.values.filter { !$0.passed }.count,
            probes: allResults.map { id, result in
                EvalProbeSummary(
                    probeId: id,
                    name: EvalProbe.standardProbes.first(where: { $0.id == id })?.name ?? id,
                    passed: result.passed,
                    isLaunchGate: EvalProbe.standardProbes.first(where: { $0.id == id })?.isLaunchGate ?? false,
                    summary: result.summary
                )
            }
        )
    }
}

// MARK: - Eval Probe Result

/// Результат выполнения eval probe.
public struct EvalProbeResult: Sendable {
    /// ID пробы.
    public let probeId: String

    /// Пройдена ли проба.
    public let passed: Bool

    /// Фактический исход.
    public let actualOutcome: EvalProbe.ExpectedOutcome

    /// Ожидаемый исход.
    public let expectedOutcome: EvalProbe.ExpectedOutcome

    /// Фактически вызванные инструменты.
    public let actualTools: [String]

    /// Ожидаемые инструменты.
    public let expectedTools: [String]

    /// Время выполнения (мс).
    public let durationMs: Double

    /// Краткое описание результата.
    public let summary: String

    /// Финальный ответ агента (если есть).
    public let finalAnswer: String?

    public init(
        probeId: String,
        passed: Bool,
        actualOutcome: EvalProbe.ExpectedOutcome,
        expectedOutcome: EvalProbe.ExpectedOutcome,
        actualTools: [String],
        expectedTools: [String],
        durationMs: Double,
        summary: String = "",
        finalAnswer: String? = nil
    ) {
        self.probeId = probeId
        self.passed = passed
        self.actualOutcome = actualOutcome
        self.expectedOutcome = expectedOutcome
        self.actualTools = actualTools
        self.expectedTools = expectedTools
        self.durationMs = durationMs
        self.summary = summary
        self.finalAnswer = finalAnswer
    }
}

// MARK: - Eval Summary

/// Сводка всех eval probes.
public struct EvalSummary: Sendable {
    public let totalProbes: Int
    public let passedProbes: Int
    public let failedProbes: Int
    public let launchGatesTotal: Int
    public let launchGatesPassed: Int
    public let launchGatesFailed: Int
    public let probes: [EvalProbeSummary]

    /// Все launch gates пройдены?
    public var allLaunchGatesPassed: Bool {
        launchGatesFailed == 0
    }

    /// Процент прохождения.
    public var passRate: Double {
        guard totalProbes > 0 else { return 0 }
        return Double(passedProbes) / Double(totalProbes)
    }
}

/// Краткая информация об одном probe.
public struct EvalProbeSummary: Sendable, Identifiable {
    public let probeId: String
    public let name: String
    public let passed: Bool
    public let isLaunchGate: Bool
    public let summary: String

    public var id: String { probeId }
}
