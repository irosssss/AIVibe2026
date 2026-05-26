// DesignAdvice.swift
// Модель ответа AI-дизайнера

import Foundation

struct DesignAdvice: Identifiable, Equatable, Codable, Sendable {
    var id: String { "\(concept.hashValue)" }

    let concept: String
    let colorPalette: [String]
    let furniture: [String]
    let lighting: [String]
    let decor: [String]
    let budget: BudgetLevel
    let provider: String

    enum BudgetLevel: String, Equatable, Codable, Sendable {
        case economy
        case medium
        case premium

        var displayName: String {
            switch self {
            case .economy:  return "Эконом"
            case .medium:   return "Средний"
            case .premium:  return "Премиум"
            }
        }
    }
}

// MARK: - Парсинг ответа AI в структуру

extension DesignAdvice {
    /// Парсит текстовый ответ от YandexGPT/GigaChat в структуру
    static func parse(from text: String, provider: String) -> DesignAdvice {
        let lines = text.components(separatedBy: "\n")

        let concept = extractSection(lines, after: "1.")
            .prefix(200)
        let colors = extractSection(lines, after: "2.")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let furniture = extractSection(lines, after: "3.")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let lighting = extractSection(lines, after: "4.")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let decor = extractSection(lines, after: "5.")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let fullText = text.lowercased()
        let budget: BudgetLevel
        if fullText.contains("премиум") {
            budget = .premium
        } else if fullText.contains("средний") {
            budget = .medium
        } else if fullText.contains("medium") {
            budget = .medium
        } else {
            budget = .economy
        }

        return DesignAdvice(
            concept: String(concept),
            colorPalette: colors.isEmpty
                ? ["Белый", "Серый", "Бежевый"]
                : colors,
            furniture: furniture.isEmpty
                ? ["Диван", "Стол", "Стулья"]
                : furniture,
            lighting: lighting.isEmpty
                ? ["Основной свет", "Торшер"]
                : lighting,
            decor: decor.isEmpty
                ? ["Картины", "Растения"]
                : decor,
            budget: budget,
            provider: provider
        )
    }

    private static func extractSection(
        _ lines: [String],
        after prefix: String
    ) -> String {
        guard let startIdx = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else {
            return ""
        }
        let nextNumbers = (2...6).map { "\($0)." }
        guard let endIdx = nextNumbers
            .compactMap { n in
                lines[startIdx+1...].firstIndex(where: { $0.hasPrefix(n) })
            }
            .min() else {
            return lines[startIdx+1...].joined(separator: "\n")
        }
        return lines[startIdx+1..<endIdx]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Equatable (ручная имплементация из-за у Identifiable)

extension DesignAdvice {
    static func == (lhs: DesignAdvice, rhs: DesignAdvice) -> Bool {
        lhs.id == rhs.id
            && lhs.concept == rhs.concept
            && lhs.budget == rhs.budget
            && lhs.provider == rhs.provider
    }
}
