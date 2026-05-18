// DesignStyle.swift
// Порт паттерна из siegblink: Modern/Vintage/Minimalist/Professional
// Расширен российскими стилями

import Foundation

enum DesignStyle: String, CaseIterable, Codable, Sendable {
    // Из siegblink
    case modern       = "modern"
    case vintage      = "vintage"
    case minimalist   = "minimalist"
    case professional = "professional"
    // Добав��ено для РФ-рынка
    case scandinavian = "scandinavian"
    case classicRussian = "classic_russian"
    case loft         = "loft"
    case eclectic     = "eclectic"

    var displayName: String {
        switch self {
        case .modern:         return "Современный"
        case .vintage:        return "Винтаж"
        case .minimalist:     return "Минимализм"
        case .professional:   return "Деловой"
        case .scandinavian:   return "Скандинавский"
        case .classicRussian: return "Классика"
        case .loft:           return "Лофт"
        case .eclectic:       return "Эклектика"
        }
    }

    var emoji: String {
        switch self {
        case .modern:         return "🏙"
        case .vintage:        return "🕰"
        case .minimalist:     return "◻️"
        case .professional:   return "💼"
        case .scandinavian:   return "🌿"
        case .classicRussian: return "🏛"
        case .loft:           return "🏭"
        case .eclectic:       return "🎨"
        }
    }

    // Ключевая функция — промпт-инжиниринг для YandexGPT
    // Перевод паттерна из siegblink: prompt = style + room + details
    var promptModifier: String {
        switch self {
        case .modern:
            return "современный стиль, чистые линии, нейтральные цвета, минимум декора"
        case .vintage:
            return "винтажный стиль, тёплые тона, состаренная мебель, ретро-детали"
        case .minimalist:
            return "минималистичный стиль, много света, только необходимое, белый и серый"
        case .professional:
            return "деловой стиль, строгость, тёмные акценты, представительность"
        case .scandinavian:
            return "скандинавский стиль, натуральное дерево, белый, уют, функциональность"
        case .classicRussian:
            return "классический стиль, симметрия, лепнина, богатые материалы, традиционность"
        case .loft:
            return "лофт-стиль, кирпич, металл, открытые коммуникации, индустриальный шик"
        case .eclectic:
            return "эклектика, смешение стилей, яркие акценты, авторский подход"
        }
    }

    // Negative prompt — заимствован из adirik/interior-design модели
    var negativePrompt: String {
        "низкое качество, размытость, деформации, людей в кадре, " +
        "неправдоподобная геометрия, нереалистичное освещение"
    }
}
