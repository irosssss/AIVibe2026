// AIVibe/Core/AI/Skills/SkillIntegration.swift
// Stage 5: Skill executor + tool guard.
// Blueprint §10: Skills — dynamic loading, execution, validation.

import Foundation
import Logging

// MARK: - Skill Executor

/// Исполняет скиллы агента — загружает инструкции и координирует вызовы инструментов.
///
/// Когда скилл активирован:
/// 1. Проверяются доступные инструменты (allowed/forbidden).
/// 2. Инструкции скилла добавляются в контекст.
/// 3. Все tool calls проходят через guard.
/// 4. Результат валидируется.
public actor SkillExecutor: Sendable {

    // MARK: - Properties

    /// Индекс скиллов.
    private let skillIndex: SkillIndex

    /// Состояния загруженных скиллов.
    private var skillStates: [String: SkillState] = [:]

    /// Счётчик вызовов инструментов per skill.
    private var toolCallCounters: [String: Int] = [:]

    /// Логгер.
    private let logger = Logger(label: "ai.skills.executor")

    // MARK: - Init

    public init(skillIndex: SkillIndex = SkillIndex()) {
        self.skillIndex = skillIndex
    }

    // MARK: - Public API

    /// Загружает скилл по ID.
    /// - Returns: Полные инструкции скилла для промпта.
    public func loadSkill(_ skillId: String) async -> String? {
        let instructions = await skillIndex.load(skillId)
        if instructions != nil {
            skillStates[skillId] = SkillState(skillId: skillId)
            toolCallCounters[skillId] = 0
            logger.info("🧩 Скилл активирован: \(skillId)")
        }
        return instructions
    }

    /// Выгружает скилл.
    public func unloadSkill(_ skillId: String) {
        Task {
            await skillIndex.unload(skillId)
        }
        skillStates.removeValue(forKey: skillId)
        toolCallCounters.removeValue(forKey: skillId)
        logger.info("🗑️ Скилл деактивирован: \(skillId)")
    }

    /// Автоматически загружает скиллы по тексту запроса.
    /// - Returns: ID загруженных скиллов.
    public func autoLoadSkills(for text: String) async -> [String] {
        let matches = await skillIndex.matchingSkills(for: text)

        var loaded: [String] = []
        for skillId in matches {
            if await skillIndex.isLoaded(skillId) { continue }
            if let _ = await loadSkill(skillId) {
                loaded.append(skillId)
            }
        }

        if !loaded.isEmpty {
            logger.info("🤖 Автозагрузка скиллов: \(loaded.joined(separator: ", "))")
        }

        return loaded
    }

    /// Отмечает вызов инструмента для активного скилла.
    public func recordToolCall(skillId: String, toolName: String) {
        toolCallCounters[skillId, default: 0] += 1

        if var state = skillStates[skillId] {
            state.toolCallsCount = toolCallCounters[skillId, default: 0]
            state.lastUsedAt = Date()
            skillStates[skillId] = state
        }

        logger.debug("🔧 \(skillId): tool call #\(toolCallCounters[skillId]!) → \(toolName)")
    }

    /// Валидирует результат работы скилла.
    public func validate(skillId: String, result: String) async -> SkillValidationResult {
        await skillIndex.validate(skillId: skillId, result: result)
    }

    /// Состояния всех активных скиллов.
    public func activeSkillStates() -> [SkillState] {
        Array(skillStates.values)
    }

    /// Сводка активных скиллов для UI.
    public func uiSummary() -> String {
        if skillStates.isEmpty {
            return "Нет активных скиллов"
        }

        return skillStates.map { (id, state) in
            "• \(id): \(state.toolCallsCount) вызовов, активен с \(state.loadedAt.formatted(.iso8601))"
        }.joined(separator: "\n")
    }
}

// MARK: - Skill Tool Guard

/// Guard: проверяет, может ли активный скилл использовать инструмент.
///
/// Если скилл запрещает инструмент — вызов блокируется.
/// Если нет активных скиллов — разрешены все инструменты.
public actor SkillToolGuard: Sendable {

    // MARK: - Properties

    /// Индекс скиллов.
    private let skillIndex: SkillIndex

    /// Логгер.
    private let logger = Logger(label: "ai.skills.guard")

    // MARK: - Init

    public init(skillIndex: SkillIndex = SkillIndex()) {
        self.skillIndex = skillIndex
    }

    // MARK: - Public API

    /// Проверяет, можно ли вызвать инструмент с текущими активными скиллами.
    ///
    /// - Parameter toolName: Имя инструмента.
    /// - Returns: `true`, если вызов разрешён.
    public func canUseTool(_ toolName: String) async -> Bool {
        let loaded = await skillIndex.loadedSkills

        // Нет активных скиллов — разрешено всё
        if loaded.isEmpty { return true }

        let canUse = await skillIndex.canUseTool(toolName)

        if !canUse {
            logger.warning("🚫 Tool Guard: \(toolName) запрещён активными скиллами (\(loaded.map { $0.id }.joined(separator: ", ")))")
        }

        return canUse
    }

    /// Возвращает список разрешённых инструментов.
    public func allowedTools() async -> [String] {
        let allowed = await skillIndex.allowedTools()
        return Array(allowed).sorted()
    }

    /// Возвращает список запрещённых инструментов.
    public func forbiddenTools() async -> [String] {
        let forbidden = await skillIndex.forbiddenTools()
        return Array(forbidden).sorted()
    }

    /// Сводка для UI.
    public func uiSummary() async -> String {
        let loaded = await skillIndex.loadedSkills
        if loaded.isEmpty {
            return "Все инструменты разрешены (нет активных скиллов)"
        }

        let allowed = await allowedTools()
        let forbidden = await forbiddenTools()

        return """
        Активные скиллы: \(loaded.map { $0.id }.joined(separator: ", "))

        ✅ Разрешены: \(allowed.joined(separator: ", "))
        🚫 Запрещены: \(forbidden.joined(separator: ", "))
        """
    }
}

// MARK: - Skill Action Request / Result

/// Запрос на действие скилла (для invoke_skill meta-tool).
public struct SkillActionRequest: Sendable, Codable {
    /// ID скилла.
    public let skillId: String

    /// Действие: load, unload, validate.
    public let action: SkillAction

    /// Опциональные параметры (для validate — результат).
    public let parameters: [String: String]?

    public enum SkillAction: String, Sendable, Codable {
        case load
        case unload
        case validate
    }

    public init(
        skillId: String,
        action: SkillAction,
        parameters: [String: String]? = nil
    ) {
        self.skillId = skillId
        self.action = action
        self.parameters = parameters
    }
}

/// Результат действия скилла.
public struct SkillActionResult: Sendable, Codable {
    /// ID скилла.
    public let skillId: String

    /// Действие.
    public let action: SkillActionRequest.SkillAction

    /// Успешно ли.
    public let success: Bool

    /// Сообщение.
    public let message: String

    /// Инструкции скилла (только для load).
    public let instructions: String?

    public init(
        skillId: String,
        action: SkillActionRequest.SkillAction,
        success: Bool,
        message: String,
        instructions: String? = nil
    ) {
        self.skillId = skillId
        self.action = action
        self.success = success
        self.message = message
        self.instructions = instructions
    }
}

// MARK: - Skill Provider (TCA Integration)

/// Провайдер скиллов — единая точка входа для агента.
///
/// Объединяет SkillIndex, SkillExecutor и SkillToolGuard.
public actor SkillProvider: Sendable {

    /// Индекс скиллов.
    public let index: SkillIndex

    /// Исполнитель скиллов.
    public let executor: SkillExecutor

    /// Guard инструментов.
    public let guard_: SkillToolGuard

    public init(skills: [AgentSkill] = AgentSkill.standardSkills) {
        let idx = SkillIndex(skills: skills)
        self.index = idx
        self.executor = SkillExecutor(skillIndex: idx)
        self.guard_ = SkillToolGuard(skillIndex: idx)
    }

    /// Обрабатывает запрос на действие скилла (для meta-tool `invoke_skill`).
    public func handleAction(_ request: SkillActionRequest) async -> SkillActionResult {
        switch request.action {
        case .load:
            if let instructions = await executor.loadSkill(request.skillId) {
                return SkillActionResult(
                    skillId: request.skillId,
                    action: .load,
                    success: true,
                    message: "Скилл \(request.skillId) загружен",
                    instructions: instructions
                )
            } else {
                return SkillActionResult(
                    skillId: request.skillId,
                    action: .load,
                    success: false,
                    message: "Скилл \(request.skillId) не найден"
                )
            }

        case .unload:
            await executor.unloadSkill(request.skillId)
            return SkillActionResult(
                skillId: request.skillId,
                action: .unload,
                success: true,
                message: "Скилл \(request.skillId) выгружен"
            )

        case .validate:
            let resultText = request.parameters?["result"] ?? ""
            let validation = await executor.validate(skillId: request.skillId, result: resultText)
            return SkillActionResult(
                skillId: request.skillId,
                action: .validate,
                success: validation.passed,
                message: validation.message
            )
        }
    }
}
