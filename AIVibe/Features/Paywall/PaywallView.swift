// AIVibe/Features/Paywall/PaywallView.swift
// Экран пейволла в стиле AIVibe DesignSystem. Якорение цен: BUSINESS делает PRO
// «дешёвым» (UX_GROWTH §6.2 п.3). Без прямых ссылок на внешнюю оплату (anti-steering).

import ComposableArchitecture
import SwiftUI

public struct PaywallScreen: View {
    private let onClose: () -> Void

    @StateObject private var host: StoreHost<PaywallFeature>

    public init(trigger: PaywallTrigger = .generic, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        _host = StateObject(wrappedValue: StoreHost<PaywallFeature>(
            Store(initialState: PaywallFeature.State(trigger: trigger)) { PaywallFeature() }
        ))
    }

    public var body: some View {
        AIThemeReader {
            PaywallView(store: host.store, onClose: onClose)
        }
    }
}

struct PaywallView: View {
    @Bindable var store: StoreOf<PaywallFeature>
    let onClose: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    private let proBenefits: [(String, String)] = [
        ("infinity", "Безлимит сканирований и вариантов"),
        ("square.and.arrow.up", "Экспорт USDZ и PDF"),
        ("photo", "HD-рендер интерьера"),
        ("rectangle.3.group", "Несколько комнат в проекте")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        titleBlock
                        benefitsList
                        tierCards
                        refreshBlock
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Блоки

    private var header: some View {
        HStack {
            Spacer()
            Button {
                Haptics.light()
                store.send(.closeTapped)
                onClose()
            } label: {
                ZStack {
                    Circle().fill(scheme == .dark
                                  ? Color(hex: 0xF1ECE2, alpha: 0.10)
                                  : Color(hex: 0x1C1916, alpha: 0.06))
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.onSurfaceMuted)
                }
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.trigger == .scanLimit
                 ? "Лимит сканирований исчерпан"
                 : "Откройте все возможности")
                .aiType(.title1)
                .foregroundStyle(c.onSurface)
            Text(store.trigger == .scanLimit
                 ? "На бесплатном тарифе доступно \(ScanQuota.freeMonthlyLimit) скана в месяц. PRO снимает ограничения."
                 : "PRO снимает лимиты и открывает экспорт, HD-рендер и мультикомнату.")
                .aiType(.body)
                .foregroundStyle(c.onSurfaceMuted)
        }
    }

    private var benefitsList: some View {
        VStack(spacing: 12) {
            ForEach(proBenefits, id: \.0) { icon, text in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(c.sandSoft)
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundStyle(c.terracotta)
                    }
                    .frame(width: 36, height: 36)

                    Text(text)
                        .aiType(.body)
                        .foregroundStyle(c.onSurface)
                    Spacer()
                }
                .padding(14)
                .background(c.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .aiSoftShadow(scheme == .dark)
            }
        }
    }

    private var tierCards: some View {
        VStack(spacing: 12) {
            ForEach([SubscriptionTier.pro, .business, .free], id: \.self) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: SubscriptionTier) -> some View {
        let isSelected = store.selectedTier == tier
        let isCurrent = store.status.effectiveTier == tier

        return Button {
            Haptics.selection()
            store.send(.tierSelected(tier))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tier.displayName)
                            .aiType(.headline)
                            .foregroundStyle(c.onSurface)
                        if isCurrent {
                            Text("Текущий")
                                .aiType(.caption)
                                .foregroundStyle(c.terracotta)
                        }
                    }
                    Text(tierSubtitle(tier))
                        .aiType(.caption)
                        .foregroundStyle(c.onSurfaceMuted)
                }
                Spacer()
                Text(tier == .free ? "0 ₽" : "\(tier.monthlyPriceRub) ₽/мес")
                    .aiType(.headline)
                    .foregroundStyle(tier == .free ? c.onSurfaceMuted : c.terracotta)
            }
            .padding(16)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? c.terracotta : .clear, lineWidth: 2)
            )
            .aiSoftShadow(scheme == .dark)
        }
        .buttonStyle(.plain)
    }

    private func tierSubtitle(_ tier: SubscriptionTier) -> String {
        switch tier {
        case .free: return "\(ScanQuota.freeMonthlyLimit) скана в месяц, 1 вариант"
        case .pro: return "Безлимит, экспорт, HD-рендер"
        case .business: return "CAD, white-label, API, приоритет AI"
        }
    }

    private var refreshBlock: some View {
        VStack(spacing: 10) {
            // Anti-steering: без прямой ссылки на внешнюю оплату из iOS-UI.
            Text("Подписка оформляется на сайте AIVibe. После оплаты вернитесь и обновите статус.")
                .aiType(.caption)
                .foregroundStyle(c.onSurfaceMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            SecondaryButton(store.isRefreshing ? "Обновляем…" : "Обновить статус") {
                Haptics.light()
                store.send(.refreshStatusTapped)
            }
            .disabled(store.isRefreshing)
        }
        .padding(.top, 4)
    }
}
