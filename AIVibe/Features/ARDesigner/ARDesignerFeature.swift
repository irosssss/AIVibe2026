// AIVibe/Features/ARDesigner/ARDesignerFeature.swift
// Reducer + DTO для экрана AR-расстановки мебели.
// Дизайн: docs/design/ai-vibe/project/ar.jsx

import ComposableArchitecture
import Foundation

// MARK: - DTO

public struct ARFurnitureItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String      // "240 см · лён"
    public let price: Int
    public let tone: AIPhotoTone
    public let market: AIMarket

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        price: Int,
        tone: AIPhotoTone,
        market: AIMarket
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.price = price
        self.tone = tone
        self.market = market
    }
}

public enum ARSheetMode: Equatable, Sendable {
    case collapsed
    case expanded
}

// MARK: - Reducer

@Reducer
public struct ARDesignerFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var roomTitle: String           // "Гостиная · Скандинавский"
        public var items: [ARFurnitureItem]
        public var sheetMode: ARSheetMode
        public var isApprovalPresented: Bool
        public var budgetMax: Int

        public init(
            roomTitle: String = "Гостиная · Скандинавский",
            items: [ARFurnitureItem] = ARDesignerFeature.mockItems,
            sheetMode: ARSheetMode = .collapsed,
            isApprovalPresented: Bool = false,
            budgetMax: Int = 350_000
        ) {
            self.roomTitle = roomTitle
            self.items = items
            self.sheetMode = sheetMode
            self.isApprovalPresented = isApprovalPresented
            self.budgetMax = budgetMax
        }

        public var totalPrice: Int {
            items.reduce(0) { $0 + $1.price }
        }

        public var budgetRatio: Double {
            guard budgetMax > 0 else { return 0 }
            return Double(totalPrice) / Double(budgetMax)
        }
    }

    public enum Action: Sendable {
        case closeTapped
        case swapProviderTapped
        case sheetToggled
        case removeItem(ARFurnitureItem.ID)
        case addToCartTapped       // открывает approval
        case approvalCancelTapped
        case approvalConfirmTapped
        case fabTapped
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .sheetToggled:
                state.sheetMode = state.sheetMode == .collapsed ? .expanded : .collapsed
                return .none

            case let .removeItem(id):
                state.items.removeAll { $0.id == id }
                return .none

            case .addToCartTapped:
                state.isApprovalPresented = true
                return .none

            case .approvalCancelTapped, .approvalConfirmTapped:
                state.isApprovalPresented = false
                return .none

            case .closeTapped, .swapProviderTapped, .fabTapped:
                return .none
            }
        }
    }

    public static let mockItems: [ARFurnitureItem] = [
        .init(title: "Диван IKEA Скандинавия", subtitle: "240 см · лён",       price: 45_990, tone: .sand,  market: .ozon),
        .init(title: "Стол круглый дуб",       subtitle: "110 см · массив",    price: 12_500, tone: .taupe, market: .wildberries),
        .init(title: "Кресло Хюгге",           subtitle: "букле, светлое",     price: 18_500, tone: .sage,  market: .wildberries),
        .init(title: "Торшер с абажуром",      subtitle: "165 см · ткань",     price:  8_990, tone: .cream, market: .ozon)
    ]
}
