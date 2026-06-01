// AIVibe/Features/RoomScan/PromptBuilder.swift
// Генерация AI-промптов из геометрии комнаты и предпочтений пользователя.

import Foundation

// MARK: - Пользовательские предпочтения

public struct UserDesignPreferences: Codable, Sendable, Equatable {
    public let style: DesignStyle
    public let budgetMin: Int?
    public let budgetMax: Int?
    public let restrictions: [String]
    public let additionalText: String?

    public init(
        style: DesignStyle,
        budgetMin: Int? = nil,
        budgetMax: Int? = nil,
        restrictions: [String] = [],
        additionalText: String? = nil
    ) {
        self.style = style
        self.budgetMin = budgetMin
        self.budgetMax = budgetMax
        self.restrictions = restrictions
        self.additionalText = additionalText
    }

    public var budgetDescription: String {
        switch (budgetMin, budgetMax) {
        case (nil, nil):
            return "бюджет не ограничен"
        case (let min?, nil):
            return "от \(min) ₽"
        case (nil, let max?):
            return "до \(max) ₽"
        case (let min?, let max?):
            return "\(min)–\(max) ₽"
        }
    }
}

// MARK: - Обратная связь пользователя

public struct UserFeedback: Codable, Sendable {
    public let dislikes: [String]
    public let keepItems: [String]
    public let freeText: String?

    public init(dislikes: [String], keepItems: [String], freeText: String? = nil) {
        self.dislikes = dislikes
        self.keepItems = keepItems
        self.freeText = freeText
    }
}

// MARK: - Протокол

public protocol PromptBuilding: Sendable {
    func buildDesignPrompt(geometry: RoomGeometry, preferences: UserDesignPreferences) -> AIPrompt
    func buildRefinePrompt(currentDesign: RoomDesignPlan, feedback: UserFeedback) -> AIPrompt
    func buildRetryPrompt(
        geometry: RoomGeometry,
        preferences: UserDesignPreferences,
        collisionInfo: String
    ) -> AIPrompt
}

// MARK: - Реализация

public struct PromptBuilder: PromptBuilding {

    public init() {}

    // MARK: Системный промпт (строительные нормы + JSON-схема)

    private static let systemPrompt = """
    Ты — эксперт по дизайну интерьеров. Ты помогаешь расставить мебель в комнате.
    Строительные нормы (обязательные):
    - Минимальная ширина прохода: не менее 70 см (основные проходы — 90 см).
    - Расстояние от мебели до стен: не менее 5 см.
    - Путь эвакуации к двери всегда свободен.
    Формат ответа: ТОЛЬКО валидный JSON без markdown-обёртки.
    JSON схема: { "items": [...], "explanation": "...", "confidence": 0.0–1.0 }
    Каждый item: { "itemType": "...", "brand": "...", "article": "...", "position": {"x":0,"y":0,"z":0}, "rotation": 0.0, "usdz_url": "", "size": {"x":0,"y":0,"z":0} }
    Размеры (size) в метрах: x=ширина, y=высота, z=глубина.
    Координаты (position) в метрах от угла комнаты (0,0,0).
    """

    // MARK: - Промпт для нового дизайна

    public func buildDesignPrompt(
        geometry: RoomGeometry,
        preferences: UserDesignPreferences
    ) -> AIPrompt {
        let userContent = buildUserContent(geometry: geometry, preferences: preferences)
        let temperature = creativityTemperature(for: preferences.style)

        return AIPrompt(
            messages: [
                ChatMessage(role: .system, content: Self.systemPrompt),
                ChatMessage(role: .user, content: userContent)
            ],
            temperature: temperature,
            maxTokens: 2000
        )
    }

    // MARK: - Промпт для уточнения дизайна

    public func buildRefinePrompt(currentDesign: RoomDesignPlan, feedback: UserFeedback) -> AIPrompt {
        var refineSystem = Self.systemPrompt
        if !feedback.keepItems.isEmpty {
            refineSystem += "\nПредметы которые НЕЛЬЗЯ изменять: \(feedback.keepItems.joined(separator: ", "))."
        }

        var userContent = "Текущий дизайн:\n"
        for item in currentDesign.items {
            userContent += "- \(item.itemType) на позиции (\(item.position.x), \(item.position.z))\n"
        }
        userContent += "\nОбъяснение: \(currentDesign.explanation)\n\n"

        if !feedback.dislikes.isEmpty {
            userContent += "Пользователю не понравилось:\n"
            userContent += feedback.dislikes.map { "- \($0)" }.joined(separator: "\n")
            userContent += "\n\n"
        }

        if let text = feedback.freeText, !text.isEmpty {
            userContent += "Пожелания пользователя: \(text)\n\n"
        }

        userContent += "Улучши дизайн, учитывая обратную связь. Верни полный JSON с обновлённым расположением."

        return AIPrompt(
            messages: [
                ChatMessage(role: .system, content: refineSystem),
                ChatMessage(role: .user, content: userContent)
            ],
            temperature: 0.5,
            maxTokens: 2000
        )
    }

    // MARK: - Повторный промпт при коллизиях

    public func buildRetryPrompt(
        geometry: RoomGeometry,
        preferences: UserDesignPreferences,
        collisionInfo: String
    ) -> AIPrompt {
        let base = buildUserContent(geometry: geometry, preferences: preferences)
        let retryContent = base + "\n\nПРЕДЫДУЩАЯ ПОПЫТКА НЕУДАЧНА:\n\(collisionInfo)\n\nИсправь расстановку, устрани коллизии."

        return AIPrompt(
            messages: [
                ChatMessage(role: .system, content: Self.systemPrompt),
                ChatMessage(role: .user, content: retryContent)
            ],
            temperature: 0.4,
            maxTokens: 2000
        )
    }

    // MARK: - Хелперы

    private func buildUserContent(geometry: RoomGeometry, preferences: UserDesignPreferences) -> String {
        var lines: [String] = []

        lines.append("Параметры комнаты:")
        lines.append("- Площадь: \(String(format: "%.1f", geometry.area)) м²")
        lines.append("- Периметр: \(String(format: "%.1f", geometry.perimeter)) м")
        lines.append("- Высота потолков: \(String(format: "%.1f", geometry.ceilingHeight)) м")
        lines.append("- Стен: \(geometry.walls.count)")
        lines.append("- Дверей: \(geometry.doors.count)")
        lines.append("- Окон: \(geometry.windows.count)")

        if !geometry.doors.isEmpty {
            let doorDesc = geometry.doors.map {
                "ширина \(String(format: "%.1f", $0.width)) м"
            }.joined(separator: ", ")
            lines.append("- Двери: \(doorDesc)")
        }

        if !geometry.windows.isEmpty {
            let winDesc = geometry.windows.map {
                "высота подоконника \(String(format: "%.1f", $0.sillHeight)) м"
            }.joined(separator: ", ")
            lines.append("- Окна: \(winDesc)")
        }

        // Если комната большая — добавляем подсказку для зонирования
        if geometry.area > 50 {
            lines.append("- Примечание: большая площадь, расставь мебель зонированием")
        }

        lines.append("")
        lines.append("Стиль: \(preferences.style.displayName) — \(preferences.style.promptModifier)")
        lines.append("Бюджет: \(preferences.budgetDescription)")

        if !preferences.restrictions.isEmpty {
            lines.append("Ограничения:")
            preferences.restrictions.forEach { lines.append("- \($0)") }
        }

        if let text = preferences.additionalText, !text.isEmpty {
            lines.append("Дополнительные пожелания: \(text)")
        }

        lines.append("")
        lines.append("Расставь мебель и верни JSON.")

        return lines.joined(separator: "\n")
    }

    // Творческие стили получают больший разброс температуры
    private func creativityTemperature(for style: DesignStyle) -> Double {
        switch style {
        case .loft, .modern, .eclectic, .vintage:
            return 0.7
        case .minimalist, .scandinavian, .professional:
            return 0.4
        case .classicRussian:
            return 0.5
        }
    }
}
