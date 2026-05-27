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
                .accessibilityHidden(true)

            // VoiceOver: невидимые элементы на позициях каждой вещи в AR-сцене.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, item in
                    Color.clear
                        .frame(width: 80, height: 60)
                        .position(arAccessibilityPoint(idx: idx, w: w, h: h))
                        .accessibilityElement()
                        .accessibilityLabel(arAccessibilityLabel(item: item, idx: idx))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
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

    /// Приблизительные позиции мебели в AR-сцене (совпадают с Canvas в ARSceneBackground).
    private func arAccessibilityPoint(idx: Int, w: CGFloat, h: CGFloat) -> CGPoint {
        switch idx {
        case 0: return CGPoint(x: w * 0.35, y: h * 0.62) // диван, слева
        case 1: return CGPoint(x: w * 0.50, y: h * 0.78) // стол, по центру
        case 2: return CGPoint(x: w * 0.83, y: h * 0.62) // кресло, справа
        case 3: return CGPoint(x: w * 0.83, y: h * 0.45) // торшер, справа вверх
        default: return CGPoint(x: w * 0.5, y: h * 0.5)
        }
    }

    private func arAccessibilityLabel(item: ARFurnitureItem, idx: Int) -> String {
        let zones = ["слева от центра", "по центру", "справа", "справа, у стены"]
        let zone = zones.indices.contains(idx) ? zones[idx] : ""
        return "\(item.title), \(item.subtitle), \(aiFmtRub(item.price)), \(zone)"
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
