// AIVibe/Features/Marketplace/PartnerCatalogClient.swift
// Живой партнёрский каталог (B2/B3/B4): поиск товаров и резолвер артикулов
// через Cloud Function marketplace. Контракт — backend/functions/marketplace/index.js.
//
// Бэкенд не сконфигурирован (BackendConfig) → методы бросают .notConfigured,
// вызывающий код деградирует в PartnerCatalogStub.

import ComposableArchitecture
import Foundation

// MARK: - Товар каталога

/// Товар партнёрского каталога в живом формате бэкенда.
public struct PartnerProduct: Identifiable, Equatable, Sendable {
    public let article: String
    public let name: String
    public let price: Int?
    public let category: String
    public let style: String
    public let widthCm: Int?
    public let depthCm: Int?
    public let heightCm: Int?
    /// Ссылка на USDZ-модель (бакет aivibe-models; файлов может ещё не быть).
    public let usdzURLString: String
    public let productURLString: String
    public let imageURLString: String
    /// AI-комментарий «подходит/не подходит» (best-effort от YandexGPT).
    public let aiReason: String?

    public var id: String { article }

    public init(
        article: String,
        name: String,
        price: Int?,
        category: String,
        style: String,
        widthCm: Int?,
        depthCm: Int?,
        heightCm: Int?,
        usdzURLString: String,
        productURLString: String,
        imageURLString: String,
        aiReason: String?
    ) {
        self.article = article
        self.name = name
        self.price = price
        self.category = category
        self.style = style
        self.widthCm = widthCm
        self.depthCm = depthCm
        self.heightCm = heightCm
        self.usdzURLString = usdzURLString
        self.productURLString = productURLString
        self.imageURLString = imageURLString
        self.aiReason = aiReason
    }
}

// MARK: - Ошибки

public enum PartnerCatalogError: LocalizedError, Sendable, Equatable {
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "URL каталога не сконфигурирован"
        }
    }
}

// MARK: - Клиент

public struct PartnerCatalogClient: Sendable {
    /// Поиск по каталогу: свободный текст + стиль (whitelist бэкенда) + бюджет.
    public var search: @Sendable (
        _ query: String,
        _ style: String?,
        _ budgetRub: Int?
    ) async throws -> [PartnerProduct]

    /// Резолвер B3: артикул → товар (или nil, если артикул не найден).
    public var resolve: @Sendable (_ article: String) async throws -> PartnerProduct?
}

// MARK: - DTO бэкенда

private struct ProductDTO: Decodable {
    let name: String?
    let price: Double?
    let url: String?
    let imageUrl: String?
    let article: String?
    let usdzUrl: String?
    let category: String?
    let style: String?
    let aiReason: String?
    // convertFromSnakeCase: width_cm → widthCm
    let widthCm: Double?
    let depthCm: Double?
    let heightCm: Double?

    var asProduct: PartnerProduct? {
        guard let article, !article.isEmpty else { return nil }
        return PartnerProduct(
            article: article,
            name: name ?? "Без названия",
            price: price.map(Int.init),
            category: category ?? "",
            style: style ?? "",
            widthCm: widthCm.map(Int.init),
            depthCm: depthCm.map(Int.init),
            heightCm: heightCm.map(Int.init),
            usdzURLString: usdzUrl ?? "",
            productURLString: url ?? "",
            imageURLString: imageUrl ?? "",
            aiReason: aiReason.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

private struct SearchRequestBody: Encodable {
    let query: String
    let roomStyle: String?
    let budget: Int?
    let userId: String
}

private struct ResolveRequestBody: Encodable {
    let action: String
    let article: String
    let userId: String
}

private struct SearchResponseBody: Decodable {
    let products: [ProductDTO]
}

private struct ResolveResponseBody: Decodable {
    let product: ProductDTO
}

// MARK: - Live

extension PartnerCatalogClient: DependencyKey {

    public static let liveValue = PartnerCatalogClient(
        search: { query, style, budgetRub in
            guard let url = BackendConfig.marketplaceURL else {
                throw PartnerCatalogError.notConfigured
            }
            let body = SearchRequestBody(
                query: query,
                roomStyle: style,
                budget: budgetRub,
                userId: AnonymousUserID.current
            )
            let response: SearchResponseBody = try await NetworkClient().post(
                url: url, body: body, headers: BackendConfig.authHeaders
            )
            return response.products.compactMap(\.asProduct)
        },
        resolve: { article in
            guard let url = BackendConfig.marketplaceURL else {
                throw PartnerCatalogError.notConfigured
            }
            let body = ResolveRequestBody(
                action: "resolve",
                article: article,
                userId: AnonymousUserID.current
            )
            do {
                let response: ResolveResponseBody = try await NetworkClient().post(
                    url: url, body: body, headers: BackendConfig.authHeaders
                )
                return response.product.asProduct
            } catch NetworkError.httpError(let statusCode, _) where statusCode == 404 {
                // Артикул не найден — штатный ответ, не ошибка.
                return nil
            }
        }
    )

    public static let testValue = PartnerCatalogClient(
        search: { _, _, _ in [] },
        resolve: { _ in nil }
    )
}

extension DependencyValues {
    public var partnerCatalogClient: PartnerCatalogClient {
        get { self[PartnerCatalogClient.self] }
        set { self[PartnerCatalogClient.self] = newValue }
    }
}
