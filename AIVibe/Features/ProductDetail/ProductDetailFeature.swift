// AIVibe/Features/ProductDetail/ProductDetailFeature.swift
// Карточка товара фабрики-партнёра + AI-комментарий + sticky действия.

import ComposableArchitecture
import Foundation

// MARK: - DTO

public struct ProductDetail: Equatable, Hashable, Sendable {
    public let market: AIMarket
    public let brand: String           // "IKEA · Угловой диван"
    public let title: String           // "Скандинавия, 240 см, светлый лён"
    public let price: Int
    public let oldPrice: Int?
    public let discountPercent: Int?
    public let rating: Double          // 4.8
    public let reviews: Int            // 124
    public let width: Int              // см
    public let depth: Int
    public let height: Int
    public let fitVerdict: String      // "Помещается в вашу гостиную"
    public let fitDetail: String       // "Займёт 58% свободного места у окна"
    public let aiCommentary: String
    public let aiProvider: String      // "YandexGPT · design_advisor"
    public let description: String
    public let photoTone: AIPhotoTone

    public init(
        market: AIMarket,
        brand: String,
        title: String,
        price: Int,
        oldPrice: Int? = nil,
        discountPercent: Int? = nil,
        rating: Double,
        reviews: Int,
        width: Int,
        depth: Int,
        height: Int,
        fitVerdict: String,
        fitDetail: String,
        aiCommentary: String,
        aiProvider: String,
        description: String,
        photoTone: AIPhotoTone = .sand
    ) {
        self.market = market
        self.brand = brand
        self.title = title
        self.price = price
        self.oldPrice = oldPrice
        self.discountPercent = discountPercent
        self.rating = rating
        self.reviews = reviews
        self.width = width
        self.depth = depth
        self.height = height
        self.fitVerdict = fitVerdict
        self.fitDetail = fitDetail
        self.aiCommentary = aiCommentary
        self.aiProvider = aiProvider
        self.description = description
        self.photoTone = photoTone
    }

    /// Демо-карточка для разработки и preview.
    public static let mock = ProductDetail(
        market: .partner,
        brand: "Фабрика «Север» · Угловой диван",
        title: "Скандинавия, 240 см, светлый лён",
        price: 45_990,
        oldPrice: 56_990,
        discountPercent: 19,
        rating: 4.8,
        reviews: 124,
        width: 240, depth: 95, height: 82,
        fitVerdict: "Помещается в вашу гостиную",
        fitDetail: "Займёт 58% свободного места у окна",
        aiCommentary: "Этот диван подходит к скандинавскому стилю вашей гостиной. Светлая льняная обивка визуально расширит пространство. Подушки можно стирать.",
        aiProvider: "YandexGPT · design_advisor",
        description: "Угловой диван-кровать с механизмом «дельфин». Обивка — лён 80%, хлопок 20%, плотность 230 г/м². Каркас из массива берёзы, наполнение — пружинный блок Bonnel плюс холлофайбер.",
        photoTone: .sand
    )
}

// MARK: - Reducer

@Reducer
public struct ProductDetailFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var product: ProductDetail
        public var isFavorite: Bool
        public var currentPage: Int        // для page-dots в hero
        public var isDescriptionExpanded: Bool
        public var isAddedToProject: Bool  // оптимистичное состояние кнопки

        public init(
            product: ProductDetail,
            isFavorite: Bool = true,
            currentPage: Int = 0,
            isDescriptionExpanded: Bool = false,
            isAddedToProject: Bool = false
        ) {
            self.product = product
            self.isFavorite = isFavorite
            self.currentPage = currentPage
            self.isDescriptionExpanded = isDescriptionExpanded
            self.isAddedToProject = isAddedToProject
        }
    }

    public enum Action: Sendable {
        case backTapped
        case shareTapped
        case favoriteToggled
        case fitCardTapped
        case descriptionExpandToggled
        case viewInARTapped
        case addToProjectTapped
        case pageChanged(Int)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .favoriteToggled:
                state.isFavorite.toggle()
                return .none
            case .descriptionExpandToggled:
                state.isDescriptionExpanded.toggle()
                return .none
            case let .pageChanged(idx):
                state.currentPage = idx
                return .none
            case .addToProjectTapped:
                state.isAddedToProject = true
                return .none
            case .backTapped, .shareTapped, .fitCardTapped, .viewInARTapped:
                return .none
            }
        }
    }
}
