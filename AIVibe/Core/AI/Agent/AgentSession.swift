// AIVibe/Core/AI/Agent/AgentSession.swift
// Stage 3: Session state — durable storage событий, планов, todo, approval records.
// Blueprint §9: Context, memory, and auto-compaction.

import Foundation
import Logging

// MARK: - AgentSession

/// Состояние сессии агента. Хранит всю историю, планы, прогресс.
///
/// Blueprint §9: Durable state (вне промпта).
///
/// ## Сохраняемое состояние
/// - `events` — все события в сессии (сообщения, tool calls, результаты)
/// - `activePlan` — текущий план дизайна (Plan Artifact)
/// - `goalState` — прогресс long-running задачи
/// - `todoList` — оставшиеся задачи
/// - `approvalRecords` — одобренные/отклонённые действия
/// - `loadedSkillIds` — активные скиллы
/// - `connectorState` — статус маркетплейсов (online/offline)
/// - `artifacts` — сгенерированные планы, списки покупок
/// - `compactionSummaries` — история compaction-сводок
/// - `providerHealth` — состояние Circuit Breaker для каждого провайдера
public actor AgentSession {

    // MARK: - Properties

    /// Уникальный идентификатор сессии.
    public let id: String

    /// ID пользователя.
    public let userId: String

    /// Максимальное количество шагов (BluePrint §4: default 8).
    public let maxSteps: Int

    /// Активный AI-провайдер для текущего шага.
    public var activeProvider: String

    /// Все события в сессии.
    private var events: [SessionEvent] = []

    /// Текущий план дизайна (может быть nil, если планирование ещё не запущено).
    public var activePlan: DesignPlan?

    /// Состояние цели (для long-running задач).
    public var goalState: GoalState?

    /// Список оставшихся задач.
    public var todoList: [TodoItem] = []

    /// Записи одобрений.
    public var approvalRecords: [ApprovalRecord] = []

    /// ID загруженных скиллов.
    public var loadedSkillIds: Set<String> = []

    /// Статус коннекторов (маркетплейсы).
    public var connectorState: [String: ConnectorStatus] = [:]

    /// Сгенерированные артефакты (ключ = тип артефакта).
    private var artifacts: [String: SessionArtifact] = [:]

    /// История compaction-сводок.
    public var compactionSummaries: [CompactionSummary] = []

    /// Состояние Circuit Breaker для каждого AI-провайдера.
    public var providerHealth: [String: ProviderHealth] = [:]

    /// Счётчик шагов.
    private var stepCount: Int = 0

    /// Логгер.
    private let logger = Logger(label: "ai.agent.session")

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        userId: String,
        maxSteps: Int = 8,
        activeProvider: String = "YandexGPT"
    ) {
        self.id = id
        self.userId = userId
        self.maxSteps = maxSteps
        self.activeProvider = activeProvider
    }

    // MARK: - Events

    /// Добавляет событие в сессию.
    public func addEvent(_ event: SessionEvent) {
        events.append(event)
        if event.isToolCall || event.isModelOutput {
            stepCount += 1
        }
        logger.debug("📝 Событие: \(event.type) (шаг \(stepCount)/\(maxSteps))")
    }

    /// Все события сессии.
    public var allEvents: [SessionEvent] {
        events
    }

    /// Только события сообщений (user/assistant).
    public var messageEvents: [SessionEvent] {
        events.filter { $0.type == .userMessage || $0.type == .modelOutput }
    }

    /// Только tool call события.
    public var toolCallEvents: [SessionEvent] {
        events.filter { $0.type == .toolCall || $0.type == .toolResult }
    }

    /// Последние N событий.
    public func recentEvents(_ count: Int = 5) -> [SessionEvent] {
        Array(events.suffix(count))
    }

    /// Текущий шаг.
    public var currentStep: Int {
        stepCount
    }

    /// Исчерпан ли бюджет шагов.
    public var isStepBudgetExhausted: Bool {
        stepCount >= maxSteps
    }

    // MARK: - Plan

    /// Устанавливает активный план дизайна.
    public func setPlan(_ plan: DesignPlan) {
        self.activePlan = plan
        logger.info("📋 План установлен: \(plan.objective)")
    }

    /// Очищает план.
    public func clearPlan() {
        self.activePlan = nil
        logger.info("🗑️ План очищен")
    }

    /// Продвигает план на следующий шаг.
    public func advancePlanStep() {
        guard var plan = activePlan else { return }
        if plan.currentStepIndex + 1 < plan.steps.count {
            plan.currentStepIndex += 1
            activePlan = plan
            logger.info("⏩ План: шаг \(plan.currentStepIndex + 1)/\(plan.steps.count) — \(plan.steps[plan.currentStepIndex])")
        }
    }

    // MARK: - Goal State

    /// Устанавливает состояние цели.
    public func setGoalState(_ state: GoalState) {
        self.goalState = state
        logger.info("🎯 Цель установлена: \(state.objective)")
    }

    /// Обновляет прогресс цели.
    public func updateGoalProgress(checkpoint: String, completed: Bool) {
        guard var state = goalState else { return }
        if completed {
            state.completedCheckpoints.insert(checkpoint)
        }
        goalState = state
        logger.info("🎯 Прогресс цели: \(state.completedCheckpoints.count)/\(state.checkpoints.count)")
    }

    // MARK: - Todo

    /// Добавляет задачу в todo.
    public func addTodo(_ item: TodoItem) {
        todoList.append(item)
    }

    /// Отмечает задачу как выполненную.
    public func completeTodo(id: String) {
        if let index = todoList.firstIndex(where: { $0.id == id }) {
            todoList[index].completed = true
            logger.info("✅ Todo выполнено: \(todoList[index].title)")
        }
    }

    /// Только невыполненные задачи.
    public var pendingTodos: [TodoItem] {
        todoList.filter { !$0.completed }
    }

    // MARK: - Approvals

    /// Добавляет запись об одобрении.
    public func addApproval(_ record: ApprovalRecord) {
        approvalRecords.append(record)
        logger.info("🔐 Одобрение: \(record.action) → \(record.decision.rawValue)")
    }

    /// Проверяет, одобрено ли действие.
    public func isApproved(action: String) -> Bool {
        approvalRecords.contains { $0.action == action && $0.decision == .approved }
    }

    // MARK: - Skills

    /// Загружает скилл.
    public func loadSkill(_ skillId: String) {
        loadedSkillIds.insert(skillId)
        logger.info("🧩 Скилл загружен: \(skillId)")
    }

    /// Выгружает скилл.
    public func unloadSkill(_ skillId: String) {
        loadedSkillIds.remove(skillId)
    }

    // MARK: - Connectors

    /// Обновляет статус коннектора.
    public func updateConnectorStatus(_ connector: String, status: ConnectorStatus) {
        connectorState[connector] = status
        logger.debug("🔌 Коннектор \(connector): \(status.rawValue)")
    }

    // MARK: - Artifacts

    /// Сохраняет артефакт.
    public func storeArtifact(_ artifact: SessionArtifact) {
        artifacts[artifact.type] = artifact
        logger.info("📦 Артефакт сохранён: \(artifact.type)")
    }

    /// Получает артефакт по типу.
    public func getArtifact(type: String) -> SessionArtifact? {
        artifacts[type]
    }

    /// Все артефакты.
    public var allArtifacts: [SessionArtifact] {
        Array(artifacts.values)
    }

    // MARK: - Compaction

    /// Добавляет compaction-сводку.
    public func addCompactionSummary(_ summary: CompactionSummary) {
        compactionSummaries.append(summary)
        logger.info("📦 Compaction выполнена: \(Int(summary.charsBefore)) → \(Int(summary.charsAfter)) символов")
    }

    /// Последняя compaction-сводка.
    public var lastCompaction: CompactionSummary? {
        compactionSummaries.last
    }

    /// Нужна ли auto-compaction (BluePrint §9: > 80% контекстного окна).
    public func needsCompaction(contextSize: Int, maxContextSize: Int = 16000) -> Bool {
        Double(contextSize) / Double(maxContextSize) > 0.8
    }

    // MARK: - Provider Health

    /// Обновляет здоровье провайдера.
    public func updateProviderHealth(_ provider: String, health: ProviderHealth) {
        providerHealth[provider] = health
    }
}

// MARK: - Session Event

/// Событие в сессии агента.
public struct SessionEvent: Identifiable, Sendable, Codable {
    public let id: String
    public let type: EventType
    public let timestamp: Date
    public let data: EventData
    public let step: Int

    public enum EventType: String, Sendable, Codable {
        case userMessage
        case modelOutput
        case toolCall
        case toolResult
        case approvalRequest
        case approvalDecision
        case compaction
        case planUpdate
        case goalUpdate
        case skillLoaded
        case skillUnloaded
        case connectorStatusChange
        case providerSwitch
        case artifactCreated
        case error
    }

    public enum EventData: Sendable, Codable {
        case text(String)
        case json(String)  // JSON-строка для структурированных данных
        case binary(Data)  // Бинарные данные (изображения, сканы)

        public var asText: String? {
            if case .text(let value) = self { return value }
            return nil
        }

        public var asJSON: String? {
            if case .json(let value) = self { return value }
            return nil
        }

        public var asBinary: Data? {
            if case .binary(let value) = self { return value }
            return nil
        }
    }

    public var isModelOutput: Bool {
        type == .modelOutput
    }

    public var isToolCall: Bool {
        type == .toolCall
    }

    public var isUserMessage: Bool {
        type == .userMessage
    }

    public init(
        id: String = UUID().uuidString,
        type: EventType,
        data: EventData,
        step: Int = 0
    ) {
        self.id = id
        self.type = type
        self.timestamp = Date()
        self.data = data
        self.step = step
    }
}

// MARK: - Design Plan (Plan Artifact)

/// План дизайна — артефакт планирования (BluePrint §7).
public struct DesignPlan: Sendable, Codable {
    public let id: String
    public let objective: String
    public let scope: String
    public let assumptions: [String]
    public let risks: [String]
    public let steps: [String]
    public let toolsRequired: [String]
    public let approvalPoints: [String]
    public let validationMethod: String
    public let rollbackRecovery: String
    public let doneCondition: String
    public var currentStepIndex: Int

    public var totalSteps: Int { steps.count }
    public var currentStep: String? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }
    public var isComplete: Bool { currentStepIndex >= steps.count }

    public init(
        id: String = UUID().uuidString,
        objective: String,
        scope: String = "",
        assumptions: [String] = [],
        risks: [String] = [],
        steps: [String] = [],
        toolsRequired: [String] = [],
        approvalPoints: [String] = [],
        validationMethod: String = "",
        rollbackRecovery: String = "",
        doneCondition: String = "",
        currentStepIndex: Int = 0
    ) {
        self.id = id
        self.objective = objective
        self.scope = scope
        self.assumptions = assumptions
        self.risks = risks
        self.steps = steps
        self.toolsRequired = toolsRequired
        self.approvalPoints = approvalPoints
        self.validationMethod = validationMethod
        self.rollbackRecovery = rollbackRecovery
        self.doneCondition = doneCondition
        self.currentStepIndex = currentStepIndex
    }
}

// MARK: - Goal State

/// Состояние цели для long-running задач (BluePrint §8).
public struct GoalState: Sendable, Codable {
    public let objective: String
    public let budget: Int
    public let checkpoints: [String]
    public var completedCheckpoints: Set<String>
    public var currentCheckpoint: String?
    public let stopRules: [String]
    public let doneCondition: String

    public var progress: Double {
        guard !checkpoints.isEmpty else { return 0 }
        return Double(completedCheckpoints.count) / Double(checkpoints.count)
    }

    public var isDone: Bool {
        completedCheckpoints.count >= checkpoints.count
    }

    public init(
        objective: String,
        budget: Int = 12,
        checkpoints: [String] = [],
        completedCheckpoints: Set<String> = [],
        currentCheckpoint: String? = nil,
        stopRules: [String] = [],
        doneCondition: String = ""
    ) {
        self.objective = objective
        self.budget = budget
        self.checkpoints = checkpoints
        self.completedCheckpoints = completedCheckpoints
        self.currentCheckpoint = currentCheckpoint
        self.stopRules = stopRules
        self.doneCondition = doneCondition
    }
}

// MARK: - Todo Item

/// Элемент списка задач.
public struct TodoItem: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public var completed: Bool
    public let createdAt: Date

    public init(id: String = UUID().uuidString, title: String, completed: Bool = false) {
        self.id = id
        self.title = title
        self.completed = completed
        self.createdAt = Date()
    }
}

// MARK: - Approval Record

/// Запись об одобрении (BluePrint §12: Audit requirements).
public struct ApprovalRecord: Identifiable, Sendable, Codable {
    public let id: String
    public let action: String
    public let riskClass: String
    public let decision: ApprovalDecision
    public let userId: String
    public let timestamp: Date
    public let reason: String?

    public enum ApprovalDecision: String, Sendable, Codable {
        case approved
        case denied
        case pending
    }

    public init(
        id: String = UUID().uuidString,
        action: String,
        riskClass: String,
        decision: ApprovalDecision,
        userId: String,
        reason: String? = nil
    ) {
        self.id = id
        self.action = action
        self.riskClass = riskClass
        self.decision = decision
        self.userId = userId
        self.timestamp = Date()
        self.reason = reason
    }
}

// MARK: - Connector Status

/// Статус внешнего коннектора.
public enum ConnectorStatus: String, Sendable, Codable {
    case online
    case offline
    case degraded
    case rateLimited
}

// MARK: - Session Artifact

/// Артефакт сессии (результат работы агента).
public struct SessionArtifact: Identifiable, Sendable, Codable {
    public let id: String
    public let type: String
    public let data: String  // JSON-строка
    public let createdAt: Date
    public let toolName: String?

    public init(
        id: String = UUID().uuidString,
        type: String,
        data: String,
        toolName: String? = nil
    ) {
        self.id = id
        self.type = type
        self.data = data
        self.createdAt = Date()
        self.toolName = toolName
    }
}

// MARK: - Compaction Summary

/// Сводка compaction (BluePrint §9).
public struct CompactionSummary: Identifiable, Sendable, Codable {
    public let id: String
    public let triggerReason: String
    public let charsBefore: Double
    public let charsAfter: Double
    public let timestamp: Date
    public let objectiveAtCompaction: String?
    public let planStepAtCompaction: String?
    public let eventsRemoved: Int

    public init(
        id: String = UUID().uuidString,
        triggerReason: String,
        charsBefore: Double,
        charsAfter: Double,
        objectiveAtCompaction: String? = nil,
        planStepAtCompaction: String? = nil,
        eventsRemoved: Int = 0
    ) {
        self.id = id
        self.triggerReason = triggerReason
        self.charsBefore = charsBefore
        self.charsAfter = charsAfter
        self.timestamp = Date()
        self.objectiveAtCompaction = objectiveAtCompaction
        self.planStepAtCompaction = planStepAtCompaction
        self.eventsRemoved = eventsRemoved
    }
}

// MARK: - Provider Health

/// Состояние здоровья AI-провайдера.
public struct ProviderHealth: Sendable, Codable {
    public let providerName: String
    public let isOnline: Bool
    public let circuitBreakerOpen: Bool
    public let cooldownRemaining: TimeInterval
    public let consecutiveFailures: Int
    public let lastLatencyMs: Double?

    public init(
        providerName: String,
        isOnline: Bool = true,
        circuitBreakerOpen: Bool = false,
        cooldownRemaining: TimeInterval = 0,
        consecutiveFailures: Int = 0,
        lastLatencyMs: Double? = nil
    ) {
        self.providerName = providerName
        self.isOnline = isOnline
        self.circuitBreakerOpen = circuitBreakerOpen
        self.cooldownRemaining = cooldownRemaining
        self.consecutiveFailures = consecutiveFailures
        self.lastLatencyMs = lastLatencyMs
    }
}
