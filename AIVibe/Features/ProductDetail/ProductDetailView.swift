// AIVibe/Features/ProductDetail/ProductDetailView.swift
// Дизайн: docs/design/ai-vibe/project/product.jsx

import ComposableArchitecture
import SwiftUI

public struct ProductDetailView: View {

    @Bindable public var store: StoreOf<ProductDetailFeature>

    let onBack: () -> Void
    let onViewInAR: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    public init(
        store: StoreOf<ProductDetailFeature>,
        onBack: @escaping () -> Void = {},
        onViewInAR: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onBack = onBack
        self.onViewInAR = onViewInAR
    }

    public var body: some View {
        AIThemeReader {
            ZStack {
                c.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroPhoto

                        bodyContent
                            .background(c.bg)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 20,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 20,
                                    style: .continuous
                                )
                            )
                            .offset(y: -20)
                    }
                }
                .ignoresSafeArea(edges: .top)

                topFloatingBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActionBar
            }
        }
    }

    // MARK: - Top floating bar (back / share / favorite)

    private var topFloatingBar: some View {
        HStack {
            pillButton("chevron.left", label: "Назад") {
                store.send(.backTapped)
                onBack()
                dismiss()
            }
            Spacer()
            HStack(spacing: 8) {
                pillButton("square.and.arrow.up", label: "Поделиться") {
                    Haptics.light()
                    store.send(.shareTapped)
                }
                pillButton(
                    store.isFavorite ? "heart.fill" : "heart",
                    tint: store.isFavorite ? c.terracotta : c.onSurface,
                    label: store.isFavorite ? "Убрать из избранного" : "В избранное"
                ) {
                    Haptics.selection()
                    store.send(.favoriteToggled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func pillButton(
        _ icon: String,
        tint: Color? = nil,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(scheme == .dark
                          ? Color.black.opacity(0.55)
                          : Color.white.opacity(0.85))
                    .background(.ultraThinMaterial, in: Circle())
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint ?? c.onSurface)
            }
            .frame(width: 36, height: 36)
            .shadow(
                color: scheme == .dark
                    ? Color.black.opacity(0.30)
                    : Color(hex: 0x1C1916, alpha: 0.08),
                radius: 4, y: 2
            )
            // Hit-area 44×44 поверх визуальных 36.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Hero photo

    private var heroPhoto: some View {
        ZStack(alignment: .bottom) {
            PhotoSlot(
                tone: store.product.photoTone,
                label: "фото товара · \(store.product.market.label.lowercased())",
                cornerRadius: 0,
                aspectRatio: nil
            )
            .frame(height: 384)

            VStack {
                HStack {
                    Chip(background: store.product.market.brandColor, foreground: .white,
                         horizontalPadding: 10, verticalPadding: 5) {
                        Text(store.product.market.label)
                    }
                    Spacer()
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule()
                            .fill(i == store.currentPage
                                  ? Color.white.opacity(0.95)
                                  : Color.white.opacity(0.45))
                            .frame(width: i == store.currentPage ? 18 : 6, height: 6)
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.top, 64)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Body sections

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleBlock
            fitCard
            dimensionsSection
            aiCommentSection
            descriptionSection
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.product.brand)
                .aiType(.caption)
                .foregroundStyle(c.onSurfaceMuted)
            Text(store.product.title)
                .aiType(.title2)
                .foregroundStyle(c.onSurface)
                .padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(aiFmtRub(store.product.price))
                    .aiType(.title1)
                    .foregroundStyle(c.onSurface)
                if let old = store.product.oldPrice {
                    Text(aiFmtRub(old))
                        .aiType(.callout)
                        .foregroundStyle(c.onSurfaceFaint)
                        .strikethrough()
                }
                if let pct = store.product.discountPercent {
                    Chip(background: c.sage, foreground: .white,
                         horizontalPadding: 8, verticalPadding: 4) {
                        Text("−\(pct)%")
                    }
                }
            }
            .padding(.top, 12)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(c.amber)
                Text(String(format: "%.1f", store.product.rating))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.onSurface)
                Text("· \(store.product.reviews) \(declension(store.product.reviews))")
                    .aiType(.callout)
                    .foregroundStyle(c.onSurfaceMuted)
            }
            .padding(.top, 8)
        }
    }

    private var fitCard: some View {
        Button {
            store.send(.fitCardTapped)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(
                        scheme == .dark
                            ? Color(hex: 0x9CB497, alpha: 0.18)
                            : Color(hex: 0x88A084, alpha: 0.16)
                    )
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(c.sage)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.product.fitVerdict)
                        .aiType(.headline)
                        .foregroundStyle(c.onSurface)
                    Text(store.product.fitDetail)
                        .aiType(.caption)
                        .foregroundStyle(c.onSurfaceMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c.onSurfaceFaint)
            }
            .padding(14)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .aiSoftShadow(scheme == .dark)
        }
        .buttonStyle(.plain)
    }

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Размеры")
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(c.sandSoft)
                    Image(systemName: "ruler")
                        .font(.system(size: 16))
                        .foregroundStyle(c.terracotta)
                }
                .frame(width: 36, height: 36)

                HStack(spacing: 18) {
                    dimensionCell("Ш", store.product.width)
                    dimensionCell("Г", store.product.depth)
                    dimensionCell("В", store.product.height)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .aiSoftShadow(scheme == .dark)
        }
    }

    private func dimensionCell(_ k: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).aiType(.caption).foregroundStyle(c.onSurfaceMuted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(v)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(c.onSurface)
                Text("см")
                    .font(.system(size: 13))
                    .foregroundStyle(c.onSurfaceMuted)
            }
        }
    }

    private var aiCommentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("AI о товаре")
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [c.sandSoft, c.terracottaSoft],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(c.terracotta)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.product.aiCommentary)
                        .aiType(.body)
                        .foregroundStyle(c.onSurface)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(c.onSurfaceFaint)
                        Text(store.product.aiProvider)
                            .font(.system(size: 11))
                            .foregroundStyle(c.onSurfaceFaint)
                    }
                }
            }
            .padding(14)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .aiSoftShadow(scheme == .dark)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Описание")
            VStack(alignment: .leading, spacing: 8) {
                Text(store.product.description)
                    .aiType(.body)
                    .foregroundStyle(c.onSurface)
                    .lineLimit(store.isDescriptionExpanded ? nil : 3)

                Button {
                    store.send(.descriptionExpandToggled)
                } label: {
                    Text(store.isDescriptionExpanded ? "Свернуть" : "Подробнее")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.terracotta)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .aiSoftShadow(scheme == .dark)
        }
    }

    // MARK: - Bottom sticky bar

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.medium()
                store.send(.viewInARTapped)
                onViewInAR()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 16))
                    Text("В AR")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(c.onSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    scheme == .dark
                        ? Color(hex: 0xF1ECE2, alpha: 0.08)
                        : Color(hex: 0x1C1916, alpha: 0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                guard !store.isAddedToProject else { return }
                Haptics.success()
                store.send(.addToProjectTapped)
            } label: {
                HStack(spacing: 6) {
                    if store.isAddedToProject {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(store.isAddedToProject ? "Добавлено" : "Добавить в проект")
                        .font(.system(size: 17, weight: .semibold))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    store.isAddedToProject ? c.sage : c.terracotta,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .animation(.spring(duration: 0.3), value: store.isAddedToProject)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .accessibilityLabel(store.isAddedToProject ? "Добавлено в проект" : "Добавить в проект")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(c.hairline)
        }
    }

    // MARK: - Helpers

    private func declension(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "отзывов" }
        if mod10 == 1 { return "отзыв" }
        if (2...4).contains(mod10) { return "отзыва" }
        return "отзывов"
    }
}

// MARK: - Public screen (encapsulates Store)

public struct ProductDetailScreen: View {
    private let product: ProductDetail
    private let onViewInAR: () -> Void
    @StateObject private var host: StoreHost<ProductDetailFeature>

    public init(
        product: ProductDetail = .mock,
        onViewInAR: @escaping () -> Void = {}
    ) {
        self.product = product
        self.onViewInAR = onViewInAR
        _host = StateObject(wrappedValue: StoreHost(
            Store(initialState: ProductDetailFeature.State(product: product)) {
                ProductDetailFeature()
            }
        ))
    }

    public var body: some View {
        ProductDetailView(store: host.store, onViewInAR: onViewInAR)
            .navigationBarBackButtonHidden(true)
    }
}
