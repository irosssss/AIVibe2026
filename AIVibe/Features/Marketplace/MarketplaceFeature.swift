// AIVibe/Features/Marketplace/MarketplaceFeature.swift
// Связан с SESSION_05: FurniturePiece.marketplace → открывает этот экран

import ComposableArchitecture
import Foundation

// Отдельная модель для Marketplace (не путать с FurniturePiece из SESSION_05)
struct MarketplaceProduct: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let price: Double?
    let url: URL
    let imageURL: URL?
    let aiReason: String       // от YandexGPT
    let marketplace: String    // "partner" — каталог фабрик (пивот 2026-06)
}

@Reducer
struct MarketplaceFeature {
    @ObservableState
    struct State: Equatable {
        var products: [MarketplaceProduct] = []
        var isLoading = false
        var query = ""
        // Переиспользуем DesignStyle из SESSION_05 — не дублируем enum
        var selectedStyle: DesignStyle = .modern
        var budget: Double?
        var error: String?

        // Если пришли из AIAdvisor (SESSION_05) — prefill запроса
        var prefillFromAdvice: DesignAdvice?
    }

    enum Action {
        case appeared                          // если prefillFromAdvice != nil — сразу поиск
        case searchTapped
        case queryChanged(String)
        case styleChanged(DesignStyle)         // DesignStyle из SESSION_05
        case budgetChanged(Double?)
        case productsLoaded(Result<[MarketplaceProduct], Error>)
        case productTapped(MarketplaceProduct) // открыть URL
        case dismissError
    }

    @Dependency(\.marketplaceClient) var client
    @Dependency(\.openURL) var openURL         // стандартная TCA dependency

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .appeared:
                // Если пришли из DesignResultView (SESSION_05) с готовым советом
                if let advice = state.prefillFromAdvice {
                    state.query = advice.furniture.first ?? ""
                    // Стиль берём из текущего состояния (установлен при навигации)
                    return .send(.searchTapped)
                }
                return .none

            case .searchTapped:
                guard !state.query.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                state.error = nil

                let query = state.query
                let style = state.selectedStyle.rawValue
                let budget = state.budget

                return .run { send in
                    let result = await Result {
                        try await client.recommend(query, style, budget)
                    }
                    await send(.productsLoaded(result))
                }

            case let .queryChanged(newQuery):
                state.query = newQuery
                return .none

            case let .styleChanged(newStyle):
                state.selectedStyle = newStyle
                return .none

            case let .budgetChanged(newBudget):
                state.budget = newBudget
                return .none

            case let .productsLoaded(.success(products)):
                state.isLoading = false
                state.products = products
                return .none

            case let .productsLoaded(.failure(err)):
                state.isLoading = false
                state.error = err.localizedDescription
                return .none

            case let .productTapped(product):
                return .run { _ in await openURL(product.url) }

            case .dismissError:
                state.error = nil
                return .none
            }
        }
    }
}

// MARK: — Client

struct MarketplaceClient {
    var recommend: @Sendable (_ query: String, _ style: String, _ budget: Double?) async throws -> [MarketplaceProduct]
}

extension MarketplaceClient: DependencyKey {
    static let liveValue = MarketplaceClient(
        recommend: { query, style, budget in
            // Живой партнёрский каталог (B2) через общий клиент: URL/токен —
            // из BackendConfig, формат — контракт functions/marketplace.
            let products = try await PartnerCatalogClient.liveValue.search(
                query, style, budget.map(Int.init)
            )
            return products.compactMap { product in
                guard let url = URL(string: product.productURLString) else { return nil }
                return MarketplaceProduct(
                    id: product.article,
                    name: product.name,
                    price: product.price.map(Double.init),
                    url: url,
                    imageURL: URL(string: product.imageURLString),
                    aiReason: product.aiReason ?? "",
                    marketplace: "partner"
                )
            }
        }
    )

    static let testValue = MarketplaceClient(
        recommend: { _, _, _ in
            guard let testURL = URL(string: "https://partner.test/p/PRT-1") else { return [] }
            return [MarketplaceProduct(
                id: "1",
                name: "Диван Осло 3-местный",
                price: 45990,
                url: testURL,
                imageURL: nil,
                aiReason: "Скандинавский дизайн идеально подходит для выбранного стиля",
                marketplace: "partner"
            )]
        }
    )
}

extension DependencyValues {
    var marketplaceClient: MarketplaceClient {
        get { self[MarketplaceClient.self] }
        set { self[MarketplaceClient.self] = newValue }
    }
}
