// DesignRequest.swift
// Аналог API-запроса к adirik/interior-design, адаптирован для YandexGPT

import UIKit
import Foundation

struct DesignRequest: Sendable {
    let roomType: RoomType
    let style: DesignStyle
    let sourceImage: UIImage
    let userComment: String?
    let promptStrength: Float

    /// Построение промпта для YandexGPT по паттерну siegblink:
    /// prompt = style_modifier + room_context + user_comment
    func buildYandexGPTPrompt() -> String {
        var parts: [String] = []

        parts.append("Ты профессиональный дизайнер интерьеров.")
        parts.append(
            "Проанализируй фотографию \(roomType.promptContext) "
            + "и предложи детальное описание редизайна."
        )
        parts.append("Стиль: \(style.promptModifier).")

        if let comment = userComment, !comment.isEmpty {
            parts.append("Дополнительное пожелание: \(comment).")
        }

        parts.append("""
        Ответ должен содержать:
        1. Описание концепции (2-3 предложения)
        2. Рекомендации по цветовой палитре (3-5 цветов с названиями)
        3. Рекомендации по мебели (5-7 позиций с конкретными названиями)
        4. Советы по освещению (2-3 рекомендации)
        5. Декор и аксессуары (3-5 позиций)
        6. Ориентировочный бюджет (эконом / средний / премиум)
        Ответ на русском языке.
        """)

        return parts.joined(separator: "\n")
    }

    /// Base64 изображения для отправки на backend
    func imageAsBase64() -> String? {
        sourceImage.jpegData(compressionQuality: 0.85)?.base64EncodedString()
    }
}
