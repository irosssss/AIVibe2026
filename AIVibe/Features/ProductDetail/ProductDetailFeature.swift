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
    /// Рейтинг/отзывы — только из реального источника. У каталога фабрик их нет → nil,
    /// блок не показывается. Синтетический рейтинг запрещён (юр-риск, закон о рекламе).
    public let rating: Double?
    public let reviews: Int?
    public let width: Int              // см
    public let depth: Int
    public let height: Int
    /// Вердикт помещаемости — только из реального расчёта геометрии (габариты товара vs комната).
    /// Нет расчёта → nil, карточка не показывается (без непроверённого «Помещается»).
    public let fitVerdict: String?
    /// Деталь подгонки из расчёта геометрии. Нет реального расчёта → nil (никаких выдуманных «%»).
    public let fitDetail: String?
    public let aiCommentary: String
    public let aiProvider: String      // "YandexGPT · design_advisor"
    public let description: String
    public let photoTone: AIPhotoTone
    /// USDZ-файл в бандле — hero-блок становится интерактивным 3D-просмотром.
    public let usdzFile: String?

    public init(
        market: AIMarket,
        brand: String,
        title: String,
        price: Int,
        oldPrice: Int? = nil,
        discountPercent: Int? = nil,
        rating: Double? = nil,
        reviews: Int? = nil,
        width: Int,
        depth: Int,
        height: Int,
        fitVerdict: String? = nil,
        fitDetail: String? = nil,
        aiCommentary: String,
        aiProvider: String,
        description: String,
        photoTone: AIPhotoTone = .sand,
        usdzFile: String? = nil
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
        self.usdzFile = usdzFile
    }

    /// Демо-карточка для разработки и preview.
    public static let mock = ProductDetail(
        market: .partner,
        brand: "Фабрика «Север» · Угловой диван",
        title: "Скандинавия, 240 см, светлый лён",
        price: 45_990,
        oldPrice: 56_990,
        discountPercent: 19,
        rating: nil,        // у каталога фабрик нет реальных отзывов
        reviews: nil,
        width: 240, depth: 95, height: 82,
        fitVerdict: "Помещается в вашу гостиную",
        fitDetail: nil,     // реального расчёта свободного места нет — без выдуманных «%»
        aiCommentary: "Этот диван подходит к скандинавскому стилю вашей гостиной. Светлая льняная обивка визуально расширит пространство. Подушки можно стирать.",
        aiProvider: "YandexGPT · design_advisor",
        description: "Угловой диван-кровать с механизмом «дельфин». Обивка — лён 80%, хлопок 20%, плотность 230 г/м². Каркас из массива берёзы, наполнение — пружинный блок Bonnel плюс холлофайбер.",
        photoTone: .sand,
        usdzFile: "sofa.usdz"
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
