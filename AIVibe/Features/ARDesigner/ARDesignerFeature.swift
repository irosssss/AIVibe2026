// AIVibe/Features/ARDesigner/ARDesignerFeature.swift
// TCA-reducer для экрана AR-расстановки мебели.
// Работает с реальным RoomDesignPlan из AgentOrchestrator pipeline.

import ComposableArchitecture
import Foundation
import simd

// MARK: - UI-режимы

public enum ARSheetMode: Equatable, Sendable {
    case collapsed
    case expanded
}

// MARK: - Reducer

@Reducer
public struct ARDesignerFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var designPlan: RoomDesignPlan
        public var roomGeometry: RoomGeometry
        public var items: IdentifiedArrayOf<FurnitureItem>
        public var selectedItemID: FurnitureItem.ID?
        public var collisionReport: CollisionReport?

        public var roomTitle: String
        public var sheetMode: ARSheetMode
        public var isApprovalPresented: Bool
        public var budgetMax: Int
        public var prices: [FurnitureItem.ID: Int]

        public var isRefining: Bool
        public var refineError: String?

        public init(
            designPlan: RoomDesignPlan,
            roomGeometry: RoomGeometry,
            roomTitle: String = "",
            sheetMode: ARSheetMode = .collapsed,
            isApprovalPresented: Bool = false,
            budgetMax: Int = 350_000,
            prices: [FurnitureItem.ID: Int] = [:]
        ) {
            self.designPlan = designPlan
            self.roomGeometry = roomGeometry
            self.items = IdentifiedArray(uniqueElements: designPlan.items)
            self.roomTitle = roomTitle
            self.sheetMode = sheetMode
            self.isApprovalPresented = isApprovalPresented
            self.budgetMax = budgetMax
            // Цены: явные (параметр) приоритетнее, иначе из предметов плана —
            // их заполняет резолвер каталога (B4) в AgentOrchestrator.
            self.prices = prices.isEmpty ? Self.pricesFromItems(designPlan.items) : prices
            self.isRefining = false
        }

        /// Цены предметов плана (заполнены резолвером каталога B4).
        static func pricesFromItems(_ items: [FurnitureItem]) -> [FurnitureItem.ID: Int] {
            Dictionary(uniqueKeysWithValues: items.compactMap { item in
                item.price.map { (item.id, $0) }
            })
        }

        public var totalPrice: Int {
            prices.values.reduce(0, +)
        }

        public var budgetRatio: Double {
            guard budgetMax > 0 else { return 0 }
            return Double(totalPrice) / Double(budgetMax)
        }

        public var selectedItem: FurnitureItem? {
            guard let id = selectedItemID else { return nil }
            return items[id: id]
        }
    }

    public enum Action: Sendable {
        case closeTapped
        case swapProviderTapped
        case sheetToggled

        case itemTapped(FurnitureItem.ID)
        case itemMoved(id: FurnitureItem.ID, newPosition: SIMD3<Float>)
        case itemRotated(id: FurnitureItem.ID, newRotation: Float)
        case removeItem(FurnitureItem.ID)

        case refineTapped
        case refineCompleted(RoomDesignPlan)
        case refineFailed(String)

        case collisionCheckCompleted(CollisionReport)

        case addToCartTapped
        case approvalCancelTapped
        case approvalConfirmTapped
        case fabTapped
    }

    @Dependency(\.agentOrchestrator) var agentOrchestrator
    @Dependency(\.collisionDetector) var collisionDetector

    private enum CancelID { case collisionCheck }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .sheetToggled:
                state.sheetMode = state.sheetMode == .collapsed ? .expanded : .collapsed
                return .none

            case let .itemTapped(id):
                state.selectedItemID = state.selectedItemID == id ? nil : id
                return .none

            case let .itemMoved(id, newPosition):
                state.items[id: id]?.position = newPosition
                return runCollisionCheck(state: state)

            case let .itemRotated(id, newRotation):
                state.items[id: id]?.rotation = newRotation
                return runCollisionCheck(state: state)

            case let .removeItem(id):
                state.items.remove(id: id)
                state.prices.removeValue(forKey: id)
                if state.selectedItemID == id { state.selectedItemID = nil }
                return runCollisionCheck(state: state)

            case .refineTapped:
                state.isRefining = true
                state.refineError = nil
                let feedback = FeedbackBuilder.buildFeedback(
                    originalPlan: state.designPlan,
                    currentItems: Array(state.items)
                )
                let plan = state.designPlan
                let geo = state.roomGeometry
                return .run { send in
                    do {
                        let refined = try await agentOrchestrator.refine(
                            plan: plan,
                            room: geo,
                            feedback: feedback
                        )
                        await send(.refineCompleted(refined))
                    } catch {
                        await send(.refineFailed(error.localizedDescription))
                    }
                }

            case let .refineCompleted(newPlan):
                state.isRefining = false
                state.designPlan = newPlan
                state.items = IdentifiedArray(uniqueElements: newPlan.items)
                state.prices = State.pricesFromItems(newPlan.items)
                state.selectedItemID = nil
                state.collisionReport = nil
                return .none

            case let .refineFailed(msg):
                state.isRefining = false
                state.refineError = msg
                return .none

            case let .collisionCheckCompleted(report):
                state.collisionReport = report
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

    private func runCollisionCheck(state: State) -> Effect<Action> {
        let items = Array(state.items)
        let geo = state.roomGeometry
        let detector = collisionDetector
        return .run { send in
            let snapshot = RoomDesignPlan(
                items: items,
                explanation: "",
                confidence: 0,
                providerName: ""
            )
            let report = detector.check(plan: snapshot, room: geo)
            await send(.collisionCheckCompleted(report))
        }
        .debounce(id: CancelID.collisionCheck, for: .milliseconds(100), scheduler: DispatchQueue.main)
    }
}
