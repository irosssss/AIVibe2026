// AIVibe/Core/AI/Connectors/WildberriesConnector.swift
// Stage 5: Wildberries Marketplace API connector.
// Blueprint §10: Connectors — external systems.

import Foundation
import Logging

// MARK: - Wildberries Connector

/// Коннектор к Wildberries API для поиска товаров в каталоге.
///
/// Blueprint §10:
/// ```
/// connector: wildberries_api
/// type: marketplace
/// endpoint: https://api.wildberries.ru/
/// auth: Yandex Lockbox (API key)
/// permissions: read_catalog, read_prices (MVP: только read)
/// version: pinned v3
/// rate_limit: 100 req/min
/// ```
public actor WildberriesConnector {

    // MARK: - Configuration

    /// Базовый URL API (v3).
    private let baseURL = "https://api.wildberries.ru"

    /// Версия API.
    public let apiVersion = "v3"

    /// Лимит запросов в минуту (Blueprint §10: 100 req/min).
    public let rateLimitPerMinute = 100

    // MARK: - State

    /// API ключ (из Yandex LockBox).
    private var apiKey: String?

    /// Счётчик запросов для rate limiting.
    private var requestCount: Int = 0
    private var windowStart: Date = Date()

    /// Логгер.
    private let logger = Logger(label: "ai.connectors.wildberries")

    // MARK: - Init

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    /// Устанавливает API ключ (из LockBox).
    public func setApiKey(_ key: String) {
        self.apiKey = key
        logger.info("🔑 Wildberries API ключ установлен")
    }

    // MARK: - Public API

    /// Поиск товаров в каталоге Wildberries.
    ///
    /// - Parameters:
    ///   - query: Поисковый запрос (например, "диван угловой серый").
    ///   - category: Категория товара (опционально, для фильтрации).
    ///   - limit: Максимальное количество результатов.
    /// - Returns: Список найденных товаров.
    public func searchProducts(
        query: String,
        category: String? = nil,
        limit: Int = 20
    ) async throws -> [WBProduct] {
        try await checkRateLimit()

        guard let apiKey = apiKey else {
            throw ConnectorError.authFailed("Wildberries API ключ не установлен")
        }

        var components = URLComponents(string: "\(baseURL)/content/v3/cards/list")!
        var queryItems = [
            URLQueryItem(name: "text", value: query),
            URLQueryItem(name: "limit", value: String(min(limit, 20)))
        ]
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        logger.debug("🔍 WB поиск: \"\(query)\" [\(category ?? "все категории")]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.networkFailed("Нет HTTP-ответа")
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let wbResponse = try decoder.decode(WBSearchResponse.self, from: data)
            let products = wbResponse.cards?.map { WBProduct(from: $0) } ?? []
            logger.info("✅ WB: найдено \(products.count) товаров")
            return products
        case 401:
            throw ConnectorError.authFailed("Wildberries: неверный API ключ")
        case 429:
            throw ConnectorError.rateLimited("Wildberries: превышен лимит запросов")
        case 500...599:
            throw ConnectorError.serverError("Wildberries: ошибка сервера (\(httpResponse.statusCode))")
        default:
            throw ConnectorError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Получает информацию о конкретном товаре по ID.
    public func getProductInfo(productId: String) async throws -> WBProduct {
        try await checkRateLimit()

        guard let apiKey = apiKey else {
            throw ConnectorError.authFailed("Wildberries API ключ не установлен")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/content/v3/cards/\(productId)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConnectorError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        let card = try decoder.decode(WBCard.self, from: data)
        return WBProduct(from: card)
    }

    /// Получает список доступных категорий.
    public func getCategories() async throws -> [WBCategory] {
        try await checkRateLimit()

        guard let apiKey = apiKey else {
            throw ConnectorError.authFailed("Wildberries API ключ не установлен")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/content/v3/categories")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConnectorError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        let categories = try decoder.decode([WBCategory].self, from: data)
        logger.info("📂 WB: \(categories.count) категорий")
        return categories
    }

    /// Проверяет наличие товара.
    public func checkStock(productId: String) async throws -> WBStockInfo {
        try await checkRateLimit()

        guard apiKey != nil else {
            throw ConnectorError.authFailed("Wildberries API ключ не установлен")
        }

        // В MVP: всегда возвращаем "в наличии" для демо
        // Реальный запрос: GET /api/v3/stocks/{warehouseId}?skus={productId}
        return WBStockInfo(
            productId: productId,
            inStock: true,
            quantity: 5,
            warehouse: "Москва"
        )
    }

    // MARK: - Rate Limiting

    /// Проверяет лимит запросов.
    private func checkRateLimit() async throws {
        let now = Date()
        // Сброс окна каждую минуту
        if now.timeIntervalSince(windowStart) >= 60 {
            requestCount = 0
            windowStart = now
        }

        if requestCount >= rateLimitPerMinute {
            let waitTime = 60 - now.timeIntervalSince(windowStart)
            if waitTime > 0 {
                logger.warning("⏳ WB rate limit: ожидание \(Int(waitTime))с")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                requestCount = 0
                windowStart = Date()
            }
        }

        requestCount += 1
    }
}

// MARK: - Data Models

/// Товар Wildberries.
public struct WBProduct: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let priceRub: Int
    public let discountedPriceRub: Int?
    public let brand: String
    public let category: String
    public let url: String
    public let thumbnailURL: String?
    public let dimensionsCm: WBDimensions?
    public let rating: Double?
    public let reviewCount: Int?
    public let inStock: Bool

    public init(from card: WBCard) {
        self.id = String(card.nmID)
        self.name = card.title
        self.priceRub = card.price
        self.discountedPriceRub = card.discountedPrice
        self.brand = card.brand
        self.category = card.category
        self.url = "https://www.wildberries.ru/catalog/\(card.nmID)/detail.aspx"
        self.thumbnailURL = card.images?.first
        self.dimensionsCm = card.dimensions.map { WBDimensions(width: $0.width, depth: $0.depth, height: $0.height) }
        self.rating = card.rating
        self.reviewCount = card.reviewCount
        self.inStock = card.quantity > 0
    }

    public init(
        id: String,
        name: String,
        priceRub: Int,
        discountedPriceRub: Int? = nil,
        brand: String = "",
        category: String = "",
        url: String = "",
        thumbnailURL: String? = nil,
        dimensionsCm: WBDimensions? = nil,
        rating: Double? = nil,
        reviewCount: Int? = nil,
        inStock: Bool = true
    ) {
        self.id = id
        self.name = name
        self.priceRub = priceRub
        self.discountedPriceRub = discountedPriceRub
        self.brand = brand
        self.category = category
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.dimensionsCm = dimensionsCm
        self.rating = rating
        self.reviewCount = reviewCount
        self.inStock = inStock
    }
}

/// Размеры товара в сантиметрах.
public struct WBDimensions: Sendable, Codable {
    public let width: Double
    public let depth: Double
    public let height: Double
}

/// Категория товара Wildberries.
public struct WBCategory: Sendable, Codable {
    public let id: Int
    public let name: String
    public let parentID: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentID = "parent_id"
    }
}

/// Информация о наличии товара.
public struct WBStockInfo: Sendable, Codable {
    public let productId: String
    public let inStock: Bool
    public let quantity: Int
    public let warehouse: String
}

// MARK: - Internal API Response Models

/// Ответ поиска Wildberries API v3.
struct WBSearchResponse: Codable {
    let cards: [WBCard]?
    let total: Int?
}

/// Карточка товара Wildberries.
struct WBCard: Codable {
    let nmID: Int
    let title: String
    let price: Int
    let discountedPrice: Int?
    let brand: String
    let category: String
    let images: [String]?
    let dimensions: WBCardDimensions?
    let rating: Double?
    let reviewCount: Int?
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case nmID = "nm_id"
        case title
        case price
        case discountedPrice = "discounted_price"
        case brand
        case category
        case images
        case dimensions
        case rating
        case reviewCount = "review_count"
        case quantity
    }
}

/// Размеры в ответе API.
struct WBCardDimensions: Codable {
    let width: Double
    let depth: Double
    let height: Double
}

// MARK: - Connector Error

/// Ошибки коннекторов (общие для всех marketplace).
public enum ConnectorError: LocalizedError, Sendable {
    case authFailed(String)
    case rateLimited(String)
    case networkFailed(String)
    case serverError(String)
    case httpError(statusCode: Int)
    case notConnected(String)

    public var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "Ошибка аутентификации: \(msg)"
        case .rateLimited(let msg): return "Превышен лимит запросов: \(msg)"
        case .networkFailed(let msg): return "Сетевая ошибка: \(msg)"
        case .serverError(let msg): return "Ошибка сервера: \(msg)"
        case .httpError(let code): return "HTTP ошибка: \(code)"
        case .notConnected(let name): return "Коннектор \(name) не подключён"
        }
    }
}

// MARK: - Connector ID

/// Идентификатор коннектора (перечисление всех внешних систем).
public enum ConnectorID: String, Sendable, Codable, CaseIterable {
    case wildberries
    case ozon

    /// Человекочитаемое имя.
    public var displayName: String {
        switch self {
        case .wildberries: return "Wildberries"
        case .ozon: return "Ozon"
        }
    }

    /// Базовый URL API.
    public var baseURL: String {
        switch self {
        case .wildberries: return "https://api.wildberries.ru"
        case .ozon: return "https://api.ozon.ru"
        }
    }
}
