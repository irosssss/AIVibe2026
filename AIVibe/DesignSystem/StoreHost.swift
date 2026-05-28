// AIVibe/DesignSystem/StoreHost.swift
// Обёртка над TCA Store для гарантированного one-time creation в SwiftUI.
//
// Проблема: при `@State private var store = Store(...)` SwiftUI вычисляет
// initialValue в init каждый раз, когда parent перерендеривает View. Сам Store
// сохраняется в @State storage, но автозамыкание `Store(...)` вызывается
// каждый раз — это wasteful (создание Reducer + Effects). А при смене
// view identity @State сбрасывается → Store пересоздаётся → loss of state +
// effect cancellation.
//
// Решение (рекомендация TCA community, до выхода TCA 2.0 с isolated stores):
// обернуть Store в ObservableObject и использовать @StateObject, который
// SwiftUI ленивит на уровне `wrappedValue` — autoclosure выполняется только
// один раз за время жизни идентичности view.

import ComposableArchitecture
import SwiftUI

@MainActor
public final class StoreHost<R: Reducer>: ObservableObject where R.State: Equatable {
    public let store: StoreOf<R>

    public init(_ make: @autoclosure () -> StoreOf<R>) {
        self.store = make()
    }
}
