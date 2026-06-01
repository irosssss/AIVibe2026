// AIVibe/Core/AI/Skills/SkillIndex.swift
// Stage 5: Skills — reusable workflows.
// Blueprint §10: Skills and connectors.

import Foundation
import Logging

// MARK: - Skill Index (actor)

/// Индекс и менеджер скиллов агента.
///
/// Blueprint §10:
/// ```
/// skill: design_advisor     — анализ комнаты и рекомендация стиля
/// skill: furniture_matcher  — подбор мебели по стилю и бюджету
/// skill: budget_optimizer   — оптимизация списка покупок по цене
/// ```
///
/// Полные инструкции скилла загружаются при выборе.
public actor SkillIndex {

    // MARK: - Properties

    /// Все доступные скиллы.
    private let skills: [AgentSkill]

    /// ID загруженных в данный момент скиллов.
    private var loadedSkillIds: Set<String> = []

    /// Инструкции загруженных скиллов (ключ = skillId).
    private var loadedInstructions: [String: String] = [:]

    /// Логгер.
    private let logger = Logger(label: "ai.skills.index")

    // MARK: - Init

    public init(skills: [AgentSkill] = AgentSkill.standardSkills) {
        self.skills = skills
    }

    // MARK: - Query

    /// Все доступные скиллы.
    public var availableSkills: [SkillInfo] {
        skills.map { $0.info }
    }

    /// Только загруженные скиллы.
    public var loadedSkills: [SkillInfo] {
        skills.filter { loadedSkillIds.contains($0.id) }.map { $0.info }
    }

    /// Проверяет, загружен ли скилл.
    public func isLoaded(_ skillId: String) -> Bool {
        loadedSkillIds.contains(skillId)
    }

    /// Возвращает скилл по ID.
    public func get(_ skillId: String) -> AgentSkill? {
        skills.first { $0.id == skillId }
    }

    // MARK: - Load / Unload

    /// Загружает скилл (добавляет инструкции в контекст).
    ///
    /// - Parameter skillId: ID скилла (например, "design_advisor").
    /// - Returns: Инструкции скилла для вставки в промпт.
    public func load(_ skillId: String) async -> String? {
        guard let skill = skills.first(where: { $0.id == skillId }) else {
            logger.warning("⚠️ Скилл не найден: \(skillId)")
            return nil
        }

        loadedSkillIds.insert(skillId)
        loadedInstructions[skillId] = skill.fullInstructions

        logger.info("🧩 Скилл загружен: \(skillId) — \(skill.info.description)")
        return skill.fullInstructions
    }

    /// Выгружает скилл.
    public func unload(_ skillId: String) {
        loadedSkillIds.remove(skillId)
        loadedInstructions.removeValue(forKey: skillId)
        logger.info("🗑️ Скилл выгружен: \(skillId)")
    }

    /// Выгружает все скиллы.
    public func unloadAll() {
        loadedSkillIds.removeAll()
        loadedInstructions.removeAll()
        logger.info("🗑️ Все скиллы выгружены")
    }

    // MARK: - Tool Access

    /// Возвращает список разрешённых инструментов для активных скиллов.
    public func allowedTools() -> Set<String> {
        var tools: Set<String> = []

        for skillId in loadedSkillIds {
            if let skill = skills.first(where: { $0.id == skillId }) {
                tools.formUnion(skill.allowedTools)
            }
        }

        // Если нет загруженных скиллов — разрешены все инструменты
        if tools.isEmpty {
            return Set(skills.flatMap { $0.allowedTools + $0.forbiddenTools })
        }

        return tools
    }

    /// Возвращает список запрещённых инструментов для активных скиллов.
    public func forbiddenTools() -> Set<String> {
        var tools: Set<String> = []

        for skillId in loadedSkillIds {
            if let skill = skills.first(where: { $0.id == skillId }) {
                tools.formUnion(skill.forbiddenTools)
            }
        }

        return tools
    }

    /// Проверяет, может ли скилл использовать инструмент.
    public func canUseTool(_ toolName: String) -> Bool {
        let forbidden = forbiddenTools()
        if forbidden.contains(toolName) { return false }

        let allowed = allowedTools()
        if allowed.isEmpty { return true }

        return allowed.contains(toolName)
    }

    /// Возвращает Skills, активные для данного запроса (по trigger phrases).
    public func matchingSkills(for text: String) -> [String] {
        skills.filter { skill in
            skill.info.triggerPhrases.contains { phrase in
                text.lowercased().contains(phrase.lowercased())
            }
        }.map { $0.id }
    }

    /// Автоматически загружает скиллы по триггер-фразам.
    public func autoLoad(for text: String) async -> [String] {
        let matches = matchingSkills(for: text)
        var loaded: [String] = []
        for skillId in matches where await load(skillId) != nil {
            loaded.append(skillId)
        }
        return loaded
    }

    // MARK: - Validation

    /// Валидирует результат работы скилла.
    public func validate(skillId: String, result: String) -> SkillValidationResult {
        guard let skill = skills.first(where: { $0.id == skillId }) else {
            return SkillValidationResult(
                skillId: skillId,
                passed: false,
                message: "Скилл \(skillId) не найден"
            )
        }

        // Проверка по описанию скилла
        switch skillId {
        case "design_advisor":
            // Должен содержать упоминание стиля
            let hasStyle = skill.info.triggerPhrases.contains { phrase in
                result.lowercased().contains(phrase.lowercased())
            } || result.contains("стиль")
            return SkillValidationResult(
                skillId: skillId,
                passed: hasStyle,
                message: hasStyle ? "OK" : "Ответ не содержит рекомендации стиля"
            )

        case "furniture_matcher":
            // Должен содержать названия мебели или цены
            let hasFurniture = ["диван", "стол", "стул", "шкаф", "кровать", "цена", "₽"]
                .contains { result.lowercased().contains($0.lowercased()) }
            return SkillValidationResult(
                skillId: skillId,
                passed: hasFurniture,
                message: hasFurniture ? "OK" : "Ответ не содержит подбора мебели"
            )

        case "budget_optimizer":
            // Должен содержать бюджет или цену
            let hasBudget = result.contains("₽") || result.contains("руб") ||
                result.contains("бюджет") || result.contains("цена")
            return SkillValidationResult(
                skillId: skillId,
                passed: hasBudget,
                message: hasBudget ? "OK" : "Ответ не содержит информации о бюджете"
            )

        default:
            return SkillValidationResult(skillId: skillId, passed: true, message: "OK")
        }
    }

    /// Формирует skill index для вставки в промпт (кратко).
    public func promptSummary() -> String {
        if loadedSkillIds.isEmpty {
            return skills.map { "• **\($0.id)**: \($0.info.description)" }
                .joined(separator: "\n")
        }

        return loadedSkills.map { skill in
            "• **\(skill.id)** [АКТИВЕН]: \(skill.description)"
        }.joined(separator: "\n")
    }
}

// MARK: - Agent Skill

/// Определение скилла агента — переиспользуемый workflow.
///
/// Blueprint §10:
/// ```
/// skill: design_advisor
/// when_to_use: "помоги с дизайном", "какой стиль", "посоветуй"
/// allowed_tools: [analyze_room_scan, recommend_style, read_resource]
/// forbidden_tools: [search_marketplace_furniture, draft_shopping_list]
/// validation: confidence > 0.6, style matches room constraints
/// ```
public struct AgentSkill: Sendable, Identifiable {

    // MARK: - Info

    /// Уникальный ID (совпадает с именем скилла).
    public let id: String

    /// Краткая информация для skill index.
    public let info: SkillInfo

    /// Разрешённые инструменты.
    public let allowedTools: [String]

    /// Запрещённые инструменты.
    public let forbiddenTools: [String]

    /// Условие валидации (опционально).
    public let validationRule: String?

    // MARK: - Full Instructions

    /// Полные инструкции скилла (вставляются в промпт при загрузке).
    public let fullInstructions: String

    // MARK: - Init

    public init(
        id: String,
        info: SkillInfo,
        allowedTools: [String],
        forbiddenTools: [String] = [],
        validationRule: String? = nil,
        fullInstructions: String
    ) {
        self.id = id
        self.info = info
        self.allowedTools = allowedTools
        self.forbiddenTools = forbiddenTools
        self.validationRule = validationRule
        self.fullInstructions = fullInstructions
    }
}

// MARK: - Standard Skills

extension AgentSkill {

    /// Стандартный набор скиллов (Blueprint §10).
    public static let standardSkills: [AgentSkill] = [
        designAdvisor,
        furnitureMatcher,
        budgetOptimizer
    ]

    // MARK: design_advisor

    public static let designAdvisor = AgentSkill(
        id: "design_advisor",
        info: SkillInfo(
            id: "design_advisor",
            description: "Анализ комнаты и рекомендация стиля интерьера",
            triggerPhrases: [
                "помоги с дизайном", "какой стиль", "посоветуй",
                "что делать с комнатой", "дизайн комнаты", "планировка"
            ],
            allowedTools: ["analyze_room_scan", "recommend_style", "read_resource"],
            forbiddenTools: ["search_marketplace_furniture", "draft_shopping_list"]
        ),
        allowedTools: ["analyze_room_scan", "recommend_style", "read_resource"],
        forbiddenTools: ["search_marketplace_furniture", "draft_shopping_list"],
        validationRule: "confidence > 0.6, style matches room constraints",
        fullInstructions: """
        ## Скилл: Design Advisor

        Ты — эксперт по дизайну интерьеров. Твоя задача — проанализировать комнату
        и порекомендовать подходящий стиль интерьера.

        ### Порядок работы
        1. Вызови `analyze_room_scan` для получения размеров, объектов, источников света.
        2. Вызови `recommend_style` с результатами анализа и предпочтениями пользователя.
        3. Представь рекомендацию пользователю.

        ### Правила
        - Учитывай размер комнаты, освещение, форму и назначение.
        - Если комната маленькая (< \(DesignNorms.smallRoomThresholdM2)м²) — рекомендуй светлые тона и минимализм.
        - Если комната тёмная (мало окон) — рекомендуй стили с хорошим искусственным освещением.
        - Всегда объясняй, ПОЧЕМУ ты рекомендуешь этот стиль.
        - Предлагай 2-3 альтернативных стиля на случай, если основной не понравится.

        ### Запрещено
        - НЕ ищи мебель на этом этапе (для этого есть furniture_matcher).
        - НЕ формируй список покупок (для этого есть budget_optimizer).
        - НЕ рекомендуй стили, несовместимые с архитектурой комнаты.
        """
    )

    // MARK: furniture_matcher

    public static let furnitureMatcher = AgentSkill(
        id: "furniture_matcher",
        info: SkillInfo(
            id: "furniture_matcher",
            description: "Подбор мебели по стилю и бюджету",
            triggerPhrases: [
                "подбери мебель", "что купить", "диван", "стол", "стул",
                "шкаф", "кровать", "полка", "освещение", "декор"
            ],
            allowedTools: ["search_marketplace_furniture", "generate_arrangement_plan"],
            forbiddenTools: ["draft_shopping_list"]
        ),
        allowedTools: ["search_marketplace_furniture", "generate_arrangement_plan"],
        forbiddenTools: ["draft_shopping_list"],
        validationRule: "все позиции in_stock, не превышен бюджет",
        fullInstructions: """
        ## Скилл: Furniture Matcher

        Ты — консультант по подбору мебели. Твоя задача — найти лучшие варианты
        мебели на российских маркетплейсах (Wildberries, Ozon) в рамках бюджета.

        ### Порядок работы
        1. Вызови `search_marketplace_furniture` для каждой категории мебели отдельно.
           - Диван: категория sofa, стиль из плана
           - Стол: категория table
           - Стулья: категория chair
           - Шкаф/полки: категория cabinet
           - Освещение: категория lamp
           - Декор: категория decor
           - Ковёр: категория rug
        2. Отфильтруй результаты по бюджету (цена ≤ оставшийся бюджет).
        3. Если товар не в наличии — ищи альтернативу.
        4. Вызови `generate_arrangement_plan` с выбранной мебелью.

        ### Правила
        - Размеры мебели должны соответствовать размерам комнаты.
        - Учитывай зоны открывания дверей (≥ \(Int(DesignNorms.doorClearanceM2)) м²).
        - Минимальная ширина прохода: \(DesignNorms.minPassageCm) см.
        - Диван — вдоль длинной стены.
        - Стол — ближе к центру комнаты.
        - Стулья — по периметру.
        - НЕ блокируй окна и батареи.

        ### Запрещено
        - НЕ формируй список покупок (для этого есть budget_optimizer).
        - НЕ превышай бюджет пользователя.
        """
    )

    // MARK: budget_optimizer

    public static let budgetOptimizer = AgentSkill(
        id: "budget_optimizer",
        info: SkillInfo(
            id: "budget_optimizer",
            description: "Оптимизация списка покупок по цене",
            triggerPhrases: [
                "дорого", "дешевле", "бюджет", "уложиться в",
                "сколько стоит", "цена", "список покупок", "итого"
            ],
            allowedTools: ["search_marketplace_furniture", "draft_shopping_list"],
            forbiddenTools: ["generate_arrangement_plan"]
        ),
        allowedTools: ["search_marketplace_furniture", "draft_shopping_list"],
        forbiddenTools: ["generate_arrangement_plan"],
        validationRule: "total_price <= budget_max",
        fullInstructions: """
        ## Скилл: Budget Optimizer

        Ты — финансовый консультант по дизайну интерьеров. Твоя задача —
        оптимизировать список покупок, чтобы уложиться в бюджет пользователя.

        ### Порядок работы
        1. Проанализируй текущий выбор мебели и общую стоимость.
        2. Если превышен бюджет:
           a. Вызови `search_marketplace_furniture` с более низким бюджетом.
           b. Предложи замену дорогих позиций на аналогичные бюджетные.
           c. Предложи отложить часть покупок на потом.
        3. Если бюджет недоиспользован (> 50%):
           a. Предложи добавить декор, освещение, растения.
        4. Вызови `draft_shopping_list` со списком выбранных товаров.

        ### Правила
        - Общий бюджет включает доставку (неявно ~\(Int(DesignNorms.deliveryShare * 100))%).
        - Приоритет: сначала крупная мебель (диван, стол), потом освещение, потом декор.
        - Если бюджет очень маленький (< \(DesignNorms.lowBudgetRub) ₽) — предложи только самое необходимое.
        - Всегда проверяй наличие товара перед добавлением в список.

        ### Советы по экономии
        - Выбирай товары со скидкой (discountedPriceRub != nil).
        - Рассмотри товары с более низким рейтингом (но ≥ \(String(format: "%.1f", DesignNorms.minAcceptableRating))).
        - Предложи отложить декор на потом — купи сначала необходимое.

        ### Запрещено
        - НЕ превышай бюджет ни при каких условиях.
        - НЕ меняй план расстановки (это делает furniture_matcher).
        """
    )
}

// MARK: - Skill State

/// Состояние загруженного скилла.
public struct SkillState: Sendable, Codable {
    public let skillId: String
    public let loadedAt: Date
    public var toolCallsCount: Int
    public var lastUsedAt: Date?

    public init(
        skillId: String,
        loadedAt: Date = Date(),
        toolCallsCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.skillId = skillId
        self.loadedAt = loadedAt
        self.toolCallsCount = toolCallsCount
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - Skill Validation Result

/// Результат валидации работы скилла.
public struct SkillValidationResult: Sendable {
    public let skillId: String
    public let passed: Bool
    public let message: String

    public init(skillId: String, passed: Bool, message: String) {
        self.skillId = skillId
        self.passed = passed
        self.message = message
    }
}
