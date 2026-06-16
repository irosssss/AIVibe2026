// AIVibe/Features/ARDesigner/DesignResponseParser.swift
// Парсинг текстового ответа LLM (может содержать markdown) в RoomDesignPlan.

import Foundation

// MARK: - Ошибки парсинга

public enum DesignResponseError: LocalizedError, Sendable, Equatable {
    case emptyResponse
    case invalidJSON(String)
    case missingRequiredFields(String)
    case confidenceOutOfRange(Double)
    case noItems

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Пустой ответ от AI-провайдера"
        case .invalidJSON(let detail):
            return "Невалидный JSON: \(detail)"
        case .missingRequiredFields(let fields):
            return "Отсутствуют обязательные поля: \(fields)"
        case .confidenceOutOfRange(let val):
            return "Confidence \(val) вне диапазона 0–1"
        case .noItems:
            return "Список предметов мебели пуст"
        }
    }
}

// MARK: - Вспомогательные типы для декодирования (file-scope для SwiftLint nesting rule)

private struct RawLLMResponse: Decodable {
    let items: [RawLLMItem]?
    let explanation: String?
    let confidence: Double?
}

private struct RawLLMItem: Decodable {
    let itemType: String?
    let item_type: String?   // snake_case вариант от LLM
    let brand: String?
    let article: String?
    let position: RawLLMVector?
    let rotation: Double?
    let usdz_url: String?
    let size: RawLLMVector?
}

private struct RawLLMVector: Decodable {
    let x: Double?
    let y: Double?
    let z: Double?
}

// MARK: - Протокол

public protocol DesignResponseParsing: Sendable {
    func parse(response: AIResponse, providerName: String) throws -> RoomDesignPlan
}

// MARK: - Реализация

public struct DesignResponseParser: DesignResponseParsing {

    public init() {}

    public func parse(response: AIResponse, providerName: String) throws -> RoomDesignPlan {
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DesignResponseError.emptyResponse }

        // Первая попытка: извлечь JSON между { и }
        let json = try extractJSON(from: text)
        let raw = try decodeRaw(json)
        return try buildPlan(from: raw, providerName: providerName)
    }

    // MARK: - JSON extraction

    private func extractJSON(from text: String) throws -> String {
        // Убираем markdown-обёртку ```json ... ```
        var cleaned = text
        if let start = cleaned.range(of: "```"),
           let end = cleaned.range(of: "```", options: .backwards),
           start != end {
            let inner = String(cleaned[start.upperBound..<end.lowerBound])
            // Убрать "json" метку после первых трёх обратных кавычек
            cleaned = inner.hasPrefix("json") ? String(inner.dropFirst(4)) : inner
        }

        // Ищем первый { и последний }
        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}") else {
            // Второй шанс: весь текст — уже JSON
            if cleaned.hasPrefix("{") { return cleaned }
            throw DesignResponseError.invalidJSON("JSON-объект не найден в ответе")
        }

        return String(cleaned[startIdx...endIdx])
    }

    // MARK: - Raw decode

    private func decodeRaw(_ json: String) throws -> RawLLMResponse {
        guard let data = json.data(using: .utf8) else {
            throw DesignResponseError.invalidJSON("Не удалось перевести строку в Data")
        }
        do {
            return try JSONDecoder().decode(RawLLMResponse.self, from: data)
        } catch {
            throw DesignResponseError.invalidJSON(error.localizedDescription)
        }
    }

    // MARK: - Построение RoomDesignPlan

    private func buildPlan(from raw: RawLLMResponse, providerName: String) throws -> RoomDesignPlan {
        guard let rawItems = raw.items, !rawItems.isEmpty else {
            throw DesignResponseError.noItems
        }

        let confidence = raw.confidence ?? 0.5
        guard (0.0...1.0).contains(confidence) else {
            throw DesignResponseError.confidenceOutOfRange(confidence)
        }

        let items = try rawItems.map { rawItem -> FurnitureItem in
            let type = rawItem.itemType ?? rawItem.item_type
            guard let itemType = type else {
                throw DesignResponseError.missingRequiredFields("itemType")
            }

            // A2: координаты LLM не запрашиваются (их считает ArrangementEngine).
            // Если LLM всё же прислала position — терпимо парсим, движок перезапишет.
            let position = SIMD3<Float>(
                Float(rawItem.position?.x ?? 0),
                Float(rawItem.position?.y ?? 0),
                Float(rawItem.position?.z ?? 0)
            )

            let size: SIMD3<Float>
            if let rawSize = rawItem.size,
               let sx = rawSize.x, let sy = rawSize.y, let sz = rawSize.z {
                size = SIMD3<Float>(Float(sx), Float(sy), Float(sz))
            } else {
                size = defaultSize(for: itemType)
            }

            return FurnitureItem(
                id: UUID(),
                itemType: itemType,
                brand: rawItem.brand ?? "",
                article: rawItem.article ?? "",
                position: position,
                rotation: Float(rawItem.rotation ?? 0),
                size: size,
                usdzURL: rawItem.usdz_url ?? ""
            )
        }

        return RoomDesignPlan(
            id: UUID(),
            items: items,
            explanation: raw.explanation ?? "",
            confidence: confidence,
            generatedAt: Date(),
            providerName: providerName
        )
    }

    // MARK: - Дефолтные размеры по типу предмета

    private func defaultSize(for itemType: String) -> SIMD3<Float> {
        switch itemType.lowercased() {
        case "sofa", "диван":       return SIMD3<Float>(2.2, 0.9, 0.95)
        case "table", "стол":       return SIMD3<Float>(1.2, 0.75, 0.8)
        case "chair", "стул":       return SIMD3<Float>(0.6, 0.9, 0.6)
        case "bed", "кровать":      return SIMD3<Float>(1.8, 0.5, 2.0)
        case "wardrobe", "шкаф":    return SIMD3<Float>(1.8, 2.2, 0.6)
        case "bookshelf", "полка":  return SIMD3<Float>(0.8, 2.0, 0.3)
        default:                    return SIMD3<Float>(1.0, 1.0, 1.0)
        }
    }
}
