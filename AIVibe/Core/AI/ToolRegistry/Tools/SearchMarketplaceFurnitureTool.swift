// AIVibe/Core/AI/ToolRegistry/Tools/SearchMarketplaceFurnitureTool.swift
// Stage 2.2: Domain-specific инструмент — поиск мебели в каталоге фабрик-партнёров.
// Blueprint §6: search_marketplace_furniture — поиск по категории, стилю, бюджету.
// Пивот 2026-06 (docs/BUSINESS_MODEL.md): маркетплейсы Ozon/WB убраны,
// единственный источник — партнёрский каталог (backend/functions/marketplace).

import Foundation

// MARK: - Output Types

/// Результат поиска одного товара (Blueprint: results).
public struct FurnitureSearchResult: Sendable, Equatable, Codable {
    /// Артикул товара в каталоге.
    public let id: String
    /// Название товара.
    public let name: String
    /// Цена в рублях.
    public let priceRub: Int
    /// Источник товара (фабрика-партнёр).
    public let marketplace: Marketplace
    /// URL страницы товара.
    public let url: String
    /// URL миниатюры.
    public let thumbnail: String
    /// Размеры в сантиметрах.
    public let dimensionsCm: FurnitureDimensions
    /// Рейтинг (0–5). nil — отзывов нет; выдумывать значение запрещено (юр-риск),
    /// фабрики-партнёры реальные отзывы пока не отдают.
    public let rating: Float?
    /// В наличии.
    public let inStock: Bool
    /// Категория.
    public let category: FurnitureCategory

    public init(
        id: String,
        name: String,
        priceRub: Int,
        marketplace: Marketplace,
        url: String,
        thumbnail: String,
        dimensionsCm: FurnitureDimensions,
        rating: Float? = nil,
        inStock: Bool = true,
        category: FurnitureCategory = .other
    ) {
        self.id = id
        self.name = name
        self.priceRub = priceRub
        self.marketplace = marketplace
        self.url = url
        self.thumbnail = thumbnail
        self.dimensionsCm = dimensionsCm
        self.rating = rating
        self.inStock = inStock
        self.category = category
    }
}

public struct FurnitureDimensions: Sendable, Equatable, Codable {
    public let w: Float
    public let d: Float
    public let h: Float

    public init(w: Float, d: Float, h: Float) {
        self.w = w
        self.d = d
        self.h = h
    }
}

/// Источник товаров. После пивота 2026-06 — только каталог фабрик-партнёров.
public enum Marketplace: String, Sendable, Equatable, Codable {
    case partner
}

public enum FurnitureCategory: String, Sendable, Equatable, Codable {
    case sofa
    case table
    case chair
    case lamp
    case cabinet
    case decor
    case rug
    case bed
    case shelf
    case other
}

public enum FurnitureStyle: String, Sendable, Equatable, Codable {
    case scandinavian
    case modern
    case loft
    case classic
    case minimal
}

// MARK: - Search Response

/// Полный ответ поиска (Blueprint output_schema).
public struct FurnitureSearchResponse: Sendable, Equatable, Codable {
    /// Найденные товары.
    public let results: [FurnitureSearchResult]
    /// Общее количество найденных.
    public let totalFound: Int
    /// Использованные маркетплейсы.
    public let searchedMarketplaces: [Marketplace]
    /// Время выполнения запроса (мс).
    public let latencyMs: Double

    public init(
        results: [FurnitureSearchResult],
        totalFound: Int,
        searchedMarketplaces: [Marketplace],
        latencyMs: Double = 0
    ) {
        self.results = results
        self.totalFound = totalFound
        self.searchedMarketplaces = searchedMarketplaces
        self.latencyMs = latencyMs
    }

    /// Сериализация в JSON-строку (для ToolResult.data).
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Tool Implementation

/// Инструмент поиска мебели в каталоге фабрик-партнёров.
///
/// Blueprint §6:
/// - risk_class: read_public_data
/// - side_effects: none
/// - permission: allow
/// - timeout: 10s
/// - max_results: 20
public struct SearchMarketplaceFurnitureTool: AgentTool {

    // MARK: - AgentTool Conformance

    public let name = "search_marketplace_furniture"
    public let description = """
    Ищет мебель в каталоге фабрик-партнёров AIVibe по категории, стилю и бюджету.
    Возвращает до 20 товаров с ценами, размерами и наличием.
    Поле rating заполнено только при наличии реальных отзывов; если оно
    отсутствует — рейтинг неизвестен, упоминать его в ответе нельзя.
    Поддерживает категории: sofa, table, chair, lamp, cabinet, decor, rug.
    Стили: scandinavian, modern, loft, classic, minimal.
    """

    public let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "query": SchemaProperty(
                type: .string,
                description: "Поисковый запрос (например, 'угловой диван серый')"
            ),
            "category": SchemaProperty(
                type: .string,
                description: "Категория мебели",
                enumValues: ["sofa", "table", "chair", "lamp", "cabinet", "decor", "rug"]
            ),
            "style": SchemaProperty(
                type: .string,
                description: "Стиль интерьера",
                enumValues: ["scandinavian", "modern", "loft", "classic", "minimal"]
            ),
            "budget_max_rub": SchemaProperty(
                type: .integer,
                description: "Максимальный бюджет на один предмет (в рублях)"
            )
        ],
        required: ["query", "category", "budget_max_rub"]
    )

    public let riskClass: ToolRiskClass = .readPublic
    public let timeout: TimeInterval = 10.0
    public let maxResultChars: Int = 8000
    public let sideEffects: ToolSideEffect = .externalRequest

    /// Максимальное количество результатов (Blueprint: max_results: 20).
    private let maxResults = 20

    // MARK: - Validation

    public func validate(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или пуст 'query'"
            )
        }
        guard let categoryStr = arguments["category"] as? String, !categoryStr.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или пуст 'category'"
            )
        }
        // Валидация категории
        guard FurnitureCategory(rawValue: categoryStr) != nil else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Некорректная категория '\(categoryStr)'. Допустимо: sofa, table, chair, lamp, cabinet, decor, rug"
            )
        }
        guard arguments["budget_max_rub"] != nil else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует 'budget_max_rub'"
            )
        }
        return arguments
    }

    // MARK: - Execute

    public func execute(validated: [String: Any]) async throws -> String {
        // swiftlint:disable force_cast
        let query = validated["query"] as! String
        let categoryStr = validated["category"] as! String
        // swiftlint:enable force_cast
        let budgetMaxRub = validated["budget_max_rub"] as? Int ?? 500_000
        let styleStr = validated["style"] as? String

        let startTime = CFAbsoluteTimeGetCurrent()

        let response: FurnitureSearchResponse

        // Реальный запрос через NetworkClient, если доступен
        #if canImport(FoundationNetworking)
        response = try await performRealSearch(
            query: query,
            category: categoryStr,
            budgetMaxRub: budgetMaxRub,
            style: styleStr
        )
        #else
        // Windows / CI: mock-поиск
        response = mockSearch(
            query: query,
            category: categoryStr,
            budgetMaxRub: budgetMaxRub,
            style: styleStr,
            startTime: startTime
        )
        #endif

        return try response.toJSON()
    }

    // MARK: - Mock Search (Windows / CI)

    /// Заглушка поиска для разработки без доступа к партнёрскому каталогу.
    /// Генерирует от 0 до maxResults реалистичных товаров.
    private func mockSearch(
        query: String,
        category: String,
        budgetMaxRub: Int,
        style: String?,
        startTime: CFAbsoluteTime
    ) -> FurnitureSearchResponse {
        let categoryEnum = FurnitureCategory(rawValue: category) ?? .other
        let styleEnum = style.flatMap { FurnitureStyle(rawValue: $0) }

        // Детерминированное количество на основе хэша запроса
        let hash = abs(query.hashValue)
        let count = min((hash % 15) + 3, maxResults)

        var results: [FurnitureSearchResult] = []

        for i in 0..<count {
            let itemId = "PRT-\(abs((hash + i).hashValue) % 1_000_000)"

            let prices: [Int] = [4500, 8900, 12_900, 18_500, 24_900, 35_000, 49_900, 65_000, 89_000, 120_000]
            let price = prices[i % prices.count]

            // Пропускаем товары дороже бюджета
            guard price <= budgetMaxRub else { continue }

            let names = furnitureNames(for: categoryEnum, style: styleEnum)
            let name = names[i % names.count]

            let dims = typicalDimensions(for: categoryEnum)

            results.append(FurnitureSearchResult(
                id: itemId,
                name: "\(name) (\(styleEnum?.rawValue ?? "универсальный"))",
                priceRub: price,
                marketplace: .partner,
                url: "https://catalog.aivibe.example/product/\(itemId)",
                thumbnail: "https://catalog.aivibe.example/img/\(itemId)_thumb.jpg",
                dimensionsCm: dims,
                rating: nil, // реальных отзывов нет — синтетический рейтинг запрещён (юр-риск)
                inStock: (hash + i) % 5 != 0, // 80% в наличии
                category: categoryEnum
            ))
        }

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return FurnitureSearchResponse(
            results: results,
            totalFound: results.count,
            searchedMarketplaces: [.partner],
            latencyMs: latency
        )
    }

    #if canImport(FoundationNetworking)
    /// Реальный HTTP-запрос к партнёрскому каталогу через NetworkClient.
    private func performRealSearch(
        query: String,
        category: String,
        budgetMaxRub: Int,
        style: String?
    ) async throws -> FurnitureSearchResponse {
        // TODO: интеграция с каталогом фабрик через backend/functions/marketplace (YDB)
        // Пока возвращает mock-результат
        return mockSearch(
            query: query,
            category: category,
            budgetMaxRub: budgetMaxRub,
            style: style,
            startTime: CFAbsoluteTimeGetCurrent()
        )
    }
    #endif

    // MARK: - Helpers

    private func furnitureNames(for category: FurnitureCategory, style: FurnitureStyle?) -> [String] {
        let stylePrefix = style.map { "\($0.rawValue) " } ?? ""

        switch category {
        case .sofa:
            return [
                "\(stylePrefix)Диван угловой",
                "\(stylePrefix)Диван прямой 3-местный",
                "\(stylePrefix)Диван-кровать",
                "\(stylePrefix)Кушетка",
                "\(stylePrefix)Модульный диван"
            ]
        case .table:
            return [
                "\(stylePrefix)Стол обеденный",
                "\(stylePrefix)Журнальный столик",
                "\(stylePrefix)Стол письменный",
                "\(stylePrefix)Стол-трансформер",
                "\(stylePrefix)Консольный столик"
            ]
        case .chair:
            return [
                "\(stylePrefix)Стул обеденный",
                "\(stylePrefix)Кресло",
                "\(stylePrefix)Барный стул",
                "\(stylePrefix)Стул складной",
                "\(stylePrefix)Пуф"
            ]
        case .lamp:
            return [
                "\(stylePrefix)Торшер",
                "\(stylePrefix)Настольная лампа",
                "\(stylePrefix)Подвесной светильник",
                "\(stylePrefix)Бра настенное",
                "\(stylePrefix)LED-лента"
            ]
        case .cabinet:
            return [
                "\(stylePrefix)Шкаф-купе",
                "\(stylePrefix)Комод",
                "\(stylePrefix)Тумба прикроватная",
                "\(stylePrefix)Стеллаж",
                "\(stylePrefix)Витрина"
            ]
        case .decor:
            return [
                "\(stylePrefix)Картина",
                "\(stylePrefix)Зеркало настенное",
                "\(stylePrefix)Ваза напольная",
                "\(stylePrefix)Кашпо",
                "\(stylePrefix)Подушка декоративная"
            ]
        case .rug:
            return [
                "\(stylePrefix)Ковёр 200×300",
                "\(stylePrefix)Ковёр 160×230",
                "\(stylePrefix)Ковёр круглый",
                "\(stylePrefix)Ковровая дорожка",
                "\(stylePrefix)Циновка"
            ]
        default:
            return [
                "\(stylePrefix)Предмет интерьера"
            ]
        }
    }

    private func typicalDimensions(for category: FurnitureCategory) -> FurnitureDimensions {
        switch category {
        case .sofa:
            return FurnitureDimensions(w: 220, d: 95, h: 85)
        case .table:
            return FurnitureDimensions(w: 140, d: 80, h: 75)
        case .chair:
            return FurnitureDimensions(w: 55, d: 50, h: 85)
        case .lamp:
            return FurnitureDimensions(w: 30, d: 30, h: 160)
        case .cabinet:
            return FurnitureDimensions(w: 200, d: 60, h: 240)
        case .decor:
            return FurnitureDimensions(w: 40, d: 5, h: 60)
        case .rug:
            return FurnitureDimensions(w: 200, d: 300, h: 1)
        default:
            return FurnitureDimensions(w: 100, d: 50, h: 100)
        }
    }
}
