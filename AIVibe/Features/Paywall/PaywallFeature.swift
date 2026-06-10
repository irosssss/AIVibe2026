// AIVibe/Features/Paywall/PaywallFeature.swift
// Пейволл FREE → PRO/BUSINESS. Показывает ценность тарифов, статус подписки
// обновляется с backend (через SubscriptionClient).
//
// ⚠️ App Store anti-steering (Guideline 3.1.1, UX_GROWTH §6.2 п.5):
// экран НЕ ведёт на внешнюю оплату напрямую — подписка оформляется на сайте,
// в приложении только информация + кнопка «Обновить статус» после оплаты.
// См. docs/UPGRADE_PLAN.md — Фаза 1, A3.3.

import ComposableArchitecture
import Foundation

/// Откуда показан пейволл — меняет заголовок (момент показа = контекст ценности).
public enum PaywallTrigger: Equatable, Sendable {
    /// Общий показ (из настроек/баннера).
    case generic
    /// Исчерпан лимит сканов FREE (3/мес).
    case scanLimit
}

@Reducer
public struct PaywallFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var trigger: PaywallTrigger
        public var status: SubscriptionStatus
        public var selectedTier: SubscriptionTier
        public var isRefreshing: Bool

        public init(
            trigger: PaywallTrigger = .generic,
            status: SubscriptionStatus = .free,
            selectedTier: SubscriptionTier = .pro,
            isRefreshing: Bool = false
        ) {
            self.trigger = trigger
            self.status = status
            self.selectedTier = selectedTier
            self.isRefreshing = isRefreshing
        }
    }

    public enum Action: Sendable {
        case onAppear
        case statusLoaded(SubscriptionStatus)
        case tierSelected(SubscriptionTier)
        case refreshStatusTapped
        case closeTapped
    }

    @Dependency(\.subscriptionClient) var subscriptionClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    let status = await subscriptionClient.fetchStatus()
                    await send(.statusLoaded(status))
                }

            case let .statusLoaded(status):
                state.status = status
                state.isRefreshing = false
                return .none

            case let .tierSelected(tier):
                state.selectedTier = tier
                return .none

            case .refreshStatusTapped:
                state.isRefreshing = true
                return .run { send in
                    let status = await subscriptionClient.fetchStatus()
                    await send(.statusLoaded(status))
                }

            case .closeTapped:
                // Закрытие обрабатывает родитель (как в RoomScanFlow).
                return .none
            }
        }
    }
}
