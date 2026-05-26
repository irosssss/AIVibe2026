// AIVibe/Core/AI/Connectors/OzonConnector.swift
// Stage 5: Ozon Marketplace API connector.
// Blueprint §10: Connectors — external systems.

import Foundation
import Logging

// MARK: - Ozon Connector

/// Коннектор к Ozon API для поиска товаров в каталоге.
///
/// Blueprint §10:
/// ```
/// connector: ozon_api
/// type: marketplace
/// endpoint: https://api.ozon.ru/
/// auth: Yandex Lockbox (API key + Client-ID)
/// permissions: read_catalog, read_prices (MVP: только read)
/// version: pinned v2
/// rate_limit: 100 req/min
/// ```
public actor OzonConnector {

    // MARK: - Configuration

    /// Базовый URL API (v2).
    private let baseURL = "https://api.ozon.ru"

    /// Версия API.
    public let apiVersion = "v2"

    /// Лимит запросов в минуту (Blueprint §10: 100 req/min).
    public let rateLimitPerMinute = 100

    // MARK: - State

    /// API ключ (из Yandex LockBox).
    private var apiKey: String?

    /// Client ID (из Yandex LockBox).
    private var clientId: String?

    /// Счётчик запросов для rate limiting.
    private var requestCount: Int = 0
    private var windowStart: Date = Date()

    /// Логгер.
    private let logger = Logger(label: "ai.connectors.ozon")

    // MARK: - Init

    public init(apiKey: String? = nil, clientId: String? = nil) {
        self.apiKey = apiKey
        self.clientId = clientId
    }

    /// Устанавливает учётные данные (из LockBox).
    public func setCredentials(apiKey: String, clientId: String) {
        self.apiKey = apiKey
        self.clientId = clientId
        logger.info("🔑 Ozon API ключ + Client-ID установлены")
    }

    // MARK: - Public API

    /// Поиск товаров в каталоге Ozon.
    ///
    /// - Parameters:
    ///   - query: Поисковый запрос.
    ///   - category: Категория товара (опционально).
    ///   - limit: Максимальное количество результатов.
    /// - Returns: Список найденных товаров.
    public func searchProducts(
        query: String,
        category: String? = nil,
        limit: Int = 20
    ) async throws -> [OzonProduct] {
        try await checkRateLimit()

        guard let apiKey = apiKey, let clientId = clientId else {
            throw ConnectorError.authFailed("Ozon: API ключ или Client-ID не установлены")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/v2/product/list")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "filter": [
                "keyword": query,
                "limit": min(limit, 20)
            ].merging(category.map { ["category_id": $0] } ?? [:]) { $1 }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("🔍 Ozon поиск: \"\(query)\" [\(category ?? "все категории")]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.networkFailed("Нет HTTP-ответа")
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let ozonResponse = try decoder.decode(OzonSearchResponse.self, from: data)
            let products = ozonResponse.result?.items?.map { OzonProduct(from: $0) } ?? []
            logger.info("✅ Ozon: найдено \(products.count) товаров")
            return products
        case 401:
            throw ConnectorError.authFailed("Ozon: неверный API ключ или Client-ID")
        case 429:
            throw ConnectorError.rateLimited("Ozon: превышен лимит запросов")
        case 500...599:
            throw ConnectorError.serverError("Ozon: ошибка сервера (\(httpResponse.statusCode))")
        default:
            throw ConnectorError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Получает информацию о конкретном товаре по ID.
    public func getProductInfo(productId: String) async throws -> OzonProduct {
        try await checkRateLimit()

        guard let apiKey = apiKey, let clientId = clientId else {
            throw ConnectorError.authFailed("Ozon: API ключ или Client-ID не установлены")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/v2/product/info")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.timeoutInterval = 10

        let body: [String: Any] = ["product_id": productId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConnectorError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        let item = try decoder.decode(OzonItem.self, from: data)
        return OzonProduct(from: item)
    }

    /// Получает список доступных категорий.
    public func getCategories() async throws -> [OzonCategory] {
        try await checkRateLimit()

        guard let apiKey = apiKey, let clientId = clientId else {
            throw ConnectorError.authFailed("Ozon: API ключ или Client-ID не установлены")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/v2/category/tree")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.timeoutInterval = 10

        let body: [String: Any] = ["language": "RU"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConnectorError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        let tree = try decoder.decode(OzonCategoryTree.self, from: data)
        logger.info("📂 Ozon: \(tree.result?.count ?? 0) категорий верхнего уровня")
        return tree.result ?? []
    }

    /// Проверяет наличие товара.
    public func checkStock(productId: String) async throws -> OzonStockInfo {
        try await checkRateLimit()

        guard apiKey != nil, clientId != nil else {
            throw ConnectorError.authFailed("Ozon: API ключ или Client-ID не установлены")
        }

        // В MVP: всегда возвращаем "в наличии" для демо
        return OzonStockInfo(
            productId: productId,
            inStock: true,
            quantity: 3,
            warehouse: "Москва"
        )
    }

    // MARK: - Rate Limiting

    /// Проверяет лимит запросов.
    private func checkRateLimit() async throws {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 60 {
            requestCount = 0
            windowStart = now
        }

        if requestCount >= rateLimitPerMinute {
            let waitTime = 60 - now.timeIntervalSince(windowStart)
            if waitTime > 0 {
                logger.warning("⏳ Ozon rate limit: ожидание \(Int(waitTime))с")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                requestCount = 0
                windowStart = Date()
            }
        }

        requestCount += 1
    }
}

// MARK: - Data Models

/// Товар Ozon.
public struct OzonProduct: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let priceRub: Int
    public let discountedPriceRub: Int?
    public let brand: String
    public let category: String
    public let url: String
    public let thumbnailURL: String?
    public let dimensionsCm: OzonDimensions?
    public let rating: Double?
    public let reviewCount: Int?
    public let inStock: Bool

    public init(from item: OzonItem) {
        self.id = String(item.id)
        self.name = item.name
        self.priceRub = Int(item.price)
        self.discountedPriceRub = item.discountedPrice.map { Int($0) }
        self.brand = item.brand ?? ""
        self.category = item.categoryName ?? ""
        self.url = "https://www.ozon.ru/product/\(item.id)"
        self.thumbnailURL = item.images?.first
        self.dimensionsCm = item.dimensions.map {
            OzonDimensions(width: $0.width, depth: $0.depth, height: $0.height)
        }
        self.rating = item.rating
        self.reviewCount = item.reviewCount
        self.inStock = item.stock > 0
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
        dimensionsCm: OzonDimensions? = nil,
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

/// Размеры товара Ozon в сантиметрах.
public struct OzonDimensions: Sendable, Codable {
    public let width: Double
    public let depth: Double
    public let height: Double
}

/// Категория товара Ozon.
public struct OzonCategory: Sendable, Codable {
    public let categoryId: Int
    public let title: String
    public let children: [OzonCategory]?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case title
        case children
    }
}

/// Информация о наличии товара Ozon.
public struct OzonStockInfo: Sendable, Codable {
    public let productId: String
    public let inStock: Bool
    public let quantity: Int
    public let warehouse: String
}

// MARK: - Internal API Response Models

/// Ответ поиска Ozon API v2.
struct OzonSearchResponse: Codable {
    let result: OzonSearchResult?
}

struct OzonSearchResult: Codable {
    let items: [OzonItem]?
    let total: Int?
}

/// Элемент товара Ozon.
struct OzonItem: Codable {
    let id: Int
    let name: String
    let price: Double
    let discountedPrice: Double?
    let brand: String?
    let categoryName: String?
    let images: [String]?
    let dimensions: OzonItemDimensions?
    let rating: Double?
    let reviewCount: Int?
    let stock: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case price
        case discountedPrice = "discounted_price"
        case brand
        case categoryName = "category_name"
        case images
        case dimensions
        case rating
        case reviewCount = "review_count"
        case stock
    }
}

/// Размеры в ответе Ozon API.
struct OzonItemDimensions: Codable {
    let width: Double
    let depth: Double
    let height: Double
}

/// Дерево категорий Ozon.
struct OzonCategoryTree: Codable {
    let result: [OzonCategory]?
}
