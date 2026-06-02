// AIVibe/Features/AIAdvisor/AIAdvisorScreen.swift
// Публичная точка входа для App-shell. Инкапсулирует Store, чтобы внешний
// модуль не зависел от internal-типов reducer'а.

import ComposableArchitecture
import SwiftUI

public struct AIAdvisorScreen: View {

    /// Снимок бюджета проекта (опционально). При наличии — рендерится бар
    /// над composer'ом.
    private let budget: BudgetSnapshot?

    /// Callback наружу: тап по карточке inline-мебели → открыть ProductDetail.
    private let onProductTap: (ChatFurnitureItem) -> Void

    /// One-time store creation через StoreHost — `@StateObject` ленивит
    /// autoclosure, не пересоздаёт Store при re-render родителя.
    @StateObject private var host: StoreHost<AIAdvisorFeature>

    public init(
        budget: BudgetSnapshot? = nil,
        onProductTap: @escaping (ChatFurnitureItem) -> Void = { _ in }
    ) {
        self.budget = budget
        self.onProductTap = onProductTap
        _host = StateObject(wrappedValue: StoreHost(
            Store(initialState: AIAdvisorFeature.State()) {
                AIAdvisorFeature()
            }
        ))
    }

    public var body: some View {
        AIAdvisorChatView(
            store: host.store,
            budget: budget,
            onProductTap: onProductTap
        )
    }
}
