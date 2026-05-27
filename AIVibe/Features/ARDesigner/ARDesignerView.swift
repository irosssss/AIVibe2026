// AIVibe/Features/ARDesigner/ARDesignerView.swift
// Симулированная AR-сцена (gradient + SwiftUI Shapes) + glass-UI overlay.
// Реальный RealityKit подключим позже — оставляем UI-shell на дизайн-проверку.

import ComposableArchitecture
import SwiftUI

// MARK: - Public entry

public struct ARDesignerScreen: View {
    private let onClose: () -> Void
    @StateObject private var host = StoreHost<ARDesignerFeature>(
        Store(initialState: ARDesignerFeature.State()) { ARDesignerFeature() }
    )

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    public var body: some View {
        ARDesignerView(store: host.store, onClose: onClose)
            .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Main view

struct ARDesignerView: View {
    @Bindable var store: StoreOf<ARDesignerFeature>
    let onClose: () -> Void

    init(store: StoreOf<ARDesignerFeature>, onClose: @escaping () -> Void = {}) {
        self.store = store
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            ARSceneBackground()
                .ignoresSafeArea()

            VStack {
                ARTopBar(
                    title: store.roomTitle,
                    onClose: {
                        Haptics.light()
                        store.send(.closeTapped)
                        onClose()
                    },
                    onSwap: {
                        Haptics.selection()
                        store.send(.swapProviderTapped)
                    }
                )
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                ARBudgetBar(
                    total: store.totalPrice,
                    max: store.budgetMax,
                    ratio: store.budgetRatio
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                ARFurnitureSheet(
                    items: store.items,
                    mode: store.sheetMode,
                    total: store.totalPrice,
                    onToggle: {
                        Haptics.selection()
                        store.send(.sheetToggled)
                    },
                    onRemove: {
                        Haptics.warning()
                        store.send(.removeItem($0))
                    },
                    onCheckout: {
                        Haptics.medium()
                        store.send(.addToCartTapped)
                    }
                )
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        store.send(.fabTapped)
                    } label: {
                        ZStack {
                            Circle().fill(Color(hex: 0xD17F62))
                                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)
                .padding(.bottom, sheetHeight + 88)
            }
        }
        .sheet(isPresented: approvalBinding) {
            ARApprovalSheet(
                items: store.items,
                total: store.totalPrice,
                onCancel: {
                    Haptics.light()
                    store.send(.approvalCancelTapped)
                },
                onConfirm: {
                    Haptics.success()
                    store.send(.approvalConfirmTapped)
                }
            )
            .presentationDetents([.large])
            .presentationBackground(.regularMaterial)
        }
        .preferredColorScheme(.dark)
    }

    /// Высота нижнего sheet (грубо), чтобы FAB не перекрывался.
    private var sheetHeight: CGFloat {
        store.sheetMode == .expanded ? 540 : 280
    }

    /// Биндинг с правильной обработкой swipe-dismiss → диспатч в reducer.
    private var approvalBinding: Binding<Bool> {
        Binding(
            get: { store.isApprovalPresented },
            set: { newValue in
                if !newValue { store.send(.approvalCancelTapped) }
            }
        )
    }
}
