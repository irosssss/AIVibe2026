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
    let marketplace: String    // "wildberries" | "ozon"
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
                    state.query = advice.furniturePieces.first?.name ?? ""
                    state.selectedStyle = advice.style
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
                        try await client.recommend(query: query, style: style, budget: budget)
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
            guard let url = URL(string: "https://functions.yandexcloud.net/YOUR_MARKETPLACE_FUNCTION_ID") else {
                throw URLError(.badURL)
            }

            let body: [String: Any] = [
                "query": query,
                "roomStyle": style,
                "budget": budget as Any,
                "userId": "current_user_id"
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 90

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            struct Response: Codable { let products: [MarketplaceProduct] }
            return try JSONDecoder().decode(Response.self, from: data).products
        }
    )

    static let testValue = MarketplaceClient(
        recommend: { _, _, _ in
            guard let testURL = URL(string: "https://wildberries.ru") else { return [] }
            return [MarketplaceProduct(
                id: "1",
                name: "Диван Осло 3-местный",
                price: 45990,
                url: testURL,
                imageURL: nil,
                aiReason: "Скандинавский дизайн идеально подходит для выбранного стиля",
                marketplace: "wildberries"
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
