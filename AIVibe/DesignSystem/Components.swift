// AIVibe/DesignSystem/Components.swift
// Базовые UI-кирпичики: Chip, MarketBadge, PrimaryButton, SecondaryButton,
// ProgressBar, BlurBar. Все согласованы с tokens.jsx + ds.jsx.

import SwiftUI

// MARK: - Chip

/// Маленький тег (например, бэйдж маркетплейса или скидка).
public struct Chip<Content: View>: View {
    public let background: Color
    public let foreground: Color
    public let horizontalPadding: CGFloat
    public let verticalPadding: CGFloat
    private let content: () -> Content

    public init(
        background: Color,
        foreground: Color,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 3,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.background = background
        self.foreground = foreground
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
    }

    public var body: some View {
        content()
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Source badge

/// Источник товара — для UI-бэйджа. Отдельный тип от Core/AI `Marketplace`,
/// чтобы DesignSystem не зависел от ToolRegistry. Мостинг — на уровне фич.
/// Пивот 2026-06: только фабрики-партнёры (docs/BUSINESS_MODEL.md).
public enum AIMarket: String, Sendable {
    case partner

    public var label: String {
        switch self {
        case .partner: return "ФАБРИКА"
        }
    }

    public var brandColor: Color {
        switch self {
        case .partner: return Color(hex: 0x88A084, alpha: 0.92)
        }
    }
}

public struct MarketBadge: View {
    public let market: AIMarket
    public init(_ market: AIMarket) { self.market = market }

    public var body: some View {
        Chip(background: market.brandColor, foreground: .white) {
            Text(market.label)
        }
    }
}

// MARK: - Primary / Secondary buttons

/// Терракотовый primary CTA. Используется по дизайну на всех сценах.
public struct PrimaryButton: View {
    public let title: String
    public let icon: String?
    public let action: () -> Void
    public let isFullWidth: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.aiColors) private var c

    public init(
        _ title: String,
        icon: String? = nil,
        isFullWidth: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.isFullWidth = isFullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.43)
            .foregroundStyle(Color.white)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
            .background(c.terracotta, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: (scheme == .dark
                        ? Color(hex: 0xD17F62, alpha: 0.28)
                        : Color(hex: 0xC2674A, alpha: 0.22)),
                radius: 12, x: 0, y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

/// Нейтральная вторичная кнопка — для "Отменить" / "Пересканировать" и т.п.
public struct SecondaryButton: View {
    public let title: String
    public let icon: String?
    public let action: () -> Void
    public let isFullWidth: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.aiColors) private var c

    public init(
        _ title: String,
        icon: String? = nil,
        isFullWidth: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.isFullWidth = isFullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.43)
            .foregroundStyle(c.onSurface)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
            .background(
                scheme == .dark
                    ? Color(hex: 0xF1ECE2, alpha: 0.08)
                    : Color(hex: 0x1C1916, alpha: 0.05),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ProgressBar

/// Тонкая progress-полоса. Цвет — семафор бюджета (sage/amber/danger).
public struct AIProgressBar: View {
    public let value: Double      // 0…1+
    public let color: Color?
    public let height: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.aiColors) private var c

    public init(value: Double, color: Color? = nil, height: CGFloat = 5) {
        self.value = value
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(scheme == .dark
                          ? Color(hex: 0xF1ECE2, alpha: 0.10)
                          : Color(hex: 0x1C1916, alpha: 0.08))
                Capsule()
                    .fill(color ?? autoColor)
                    .frame(width: geo.size.width * max(0, min(value, 1)))
            }
        }
        .frame(height: height)
    }

    /// Семафор по проценту бюджета.
    private var autoColor: Color {
        if value < 0.8 { return c.sage }
        if value < 1.0 { return c.amber }
        return c.danger
    }
}

// MARK: - BlurBar (frosted material под нативный iOS chrome)

/// Универсальный полупрозрачный фон. Используется как фон композеров, top-bar,
/// tab-bar — там, где в дизайне `backdropFilter: blur(24px)`.
public struct BlurBar<Content: View>: View {
    public let material: Material
    public let cornerRadius: CGFloat
    private let content: () -> Content

    public init(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var body: some View {
        content()
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Section header

/// Заголовок секции с опциональным trailing-действием (например, "Все").
public struct SectionHeader: View {
    public let title: String
    public let trailing: String?
    public let trailingAction: (() -> Void)?

    @Environment(\.aiColors) private var c

    public init(_ title: String, trailing: String? = nil, trailingAction: (() -> Void)? = nil) {
        self.title = title
        self.trailing = trailing
        self.trailingAction = trailingAction
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .aiType(.title3)
                .foregroundStyle(c.onSurface)
            Spacer(minLength: 8)
            if let trailing {
                Button {
                    trailingAction?()
                } label: {
                    Text(trailing)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.terracotta)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Caption-label (uppercase, tracked)

/// Маленький заголовок-капс ("ИДЕЯ ОТ AI", "ОБНАРУЖЕНО", "РАЗМЕРЫ").
public struct CapsLabel: View {
    public let text: String
    public let color: Color?

    @Environment(\.aiColors) private var c

    public init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color ?? c.onSurfaceMuted)
    }
}

#Preview {
    AIThemeReader {
        VStack(spacing: 16) {
            HStack { MarketBadge(.partner) }
            PrimaryButton("Начать сканирование", icon: "viewfinder")
            SecondaryButton("Пересканировать")
            AIProgressBar(value: 0.7).frame(width: 240)
            SectionHeader("Текущие проекты", trailing: "Все")
            CapsLabel("Идея от AI")
        }
        .padding()
        .background(AIColors.light.bg)
    }
}
