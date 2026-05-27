// AIVibe/DesignSystem/Theme.swift
// Палитра, типографика, тени, форматтеры.
// Источник истины: docs/design/ai-vibe/project/tokens.jsx

import SwiftUI

// MARK: - Палитра

/// Цвета AIVibe — тёплая земляная гамма, light + dark варианты.
/// Используется через `AIColors.current(scheme)` или environment-based extension `Color`.
public struct AIColors: Sendable {

    public let bg: Color
    public let bgSubtle: Color
    public let surface: Color
    public let elevated: Color

    public let onSurface: Color
    public let onSurfaceMuted: Color
    public let onSurfaceFaint: Color

    public let divider: Color
    public let hairline: Color

    public let terracotta: Color
    public let terracottaSoft: Color
    public let sage: Color
    public let sageSoft: Color
    public let sand: Color
    public let sandSoft: Color
    public let amber: Color
    public let danger: Color

    public let fieldBg: Color

    public static let light = AIColors(
        bg:               Color(hex: 0xF6F2EB),
        bgSubtle:         Color(hex: 0xEFEAE1),
        surface:          Color(hex: 0xFFFCF6),
        elevated:         Color(hex: 0xFFFFFF),
        onSurface:        Color(hex: 0x1C1916),
        onSurfaceMuted:   Color(hex: 0x6E665B),
        onSurfaceFaint:   Color(hex: 0xA39B8E),
        divider:          Color(hex: 0x1C1916, alpha: 0.08),
        hairline:         Color(hex: 0x1C1916, alpha: 0.06),
        terracotta:       Color(hex: 0xC2674A),
        terracottaSoft:   Color(hex: 0xE8C9BC),
        sage:             Color(hex: 0x88A084),
        sageSoft:         Color(hex: 0xCFDCC8),
        sand:             Color(hex: 0xD6B589),
        sandSoft:         Color(hex: 0xEFE0C2),
        amber:            Color(hex: 0xDD9F4A),
        danger:           Color(hex: 0xB5503A),
        fieldBg:          Color(hex: 0xEFEAE1)
    )

    public static let dark = AIColors(
        bg:               Color(hex: 0x15130F),
        bgSubtle:         Color(hex: 0x1A1814),
        surface:          Color(hex: 0x1F1C17),
        elevated:         Color(hex: 0x2A2620),
        onSurface:        Color(hex: 0xF1ECE2),
        onSurfaceMuted:   Color(hex: 0xA09889),
        onSurfaceFaint:   Color(hex: 0x6E665B),
        divider:          Color(hex: 0xF1ECE2, alpha: 0.10),
        hairline:         Color(hex: 0xF1ECE2, alpha: 0.07),
        terracotta:       Color(hex: 0xD17F62),
        terracottaSoft:   Color(hex: 0x4A2E22),
        sage:             Color(hex: 0x9CB497),
        sageSoft:         Color(hex: 0x2E3A2C),
        sand:             Color(hex: 0xE0C091),
        sandSoft:         Color(hex: 0x3D3325),
        amber:            Color(hex: 0xE5AC5F),
        danger:           Color(hex: 0xC2624A),
        fieldBg:          Color(hex: 0x2A2620)
    )

    /// Возвращает палитру под текущую colorScheme.
    public static func current(_ scheme: ColorScheme) -> AIColors {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Environment-доступ к палитре

private struct AIColorsKey: EnvironmentKey {
    static let defaultValue: AIColors = .light
}

extension EnvironmentValues {
    /// `@Environment(\.aiColors)` — авторазрешение по `colorScheme`.
    /// Установка происходит в `AIThemeReader`.
    public var aiColors: AIColors {
        get { self[AIColorsKey.self] }
        set { self[AIColorsKey.self] = newValue }
    }
}

/// Обёртка-корень, прокидывающая `AIColors` в environment согласно colorScheme.
/// Применять у корня каждой top-level вью (либо у корня приложения).
public struct AIThemeReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .environment(\.aiColors, AIColors.current(scheme))
    }
}

// MARK: - Типографика (8 ролей по Apple HIG)

/// Роли SF Pro по Apple HIG. Размеры из tokens.jsx совпадают с Apple-defaults
/// (largeTitle 34, title1 28, …), поэтому маппим на `Font.TextStyle` и получаем
/// Dynamic Type «бесплатно» — шрифт масштабируется под пользовательские настройки
/// доступности (xxxLarge, accessibility1…5).
public enum AIType: Sendable {
    case largeTitle, title1, title2, title3, headline, body, callout, caption

    public struct Spec: Sendable {
        public let size: CGFloat
        public let weight: Font.Weight
        public let leading: CGFloat
        public let tracking: CGFloat
    }

    public var spec: Spec {
        switch self {
        case .largeTitle: return .init(size: 34, weight: .bold,     leading: 41, tracking: 0.37)
        case .title1:     return .init(size: 28, weight: .bold,     leading: 34, tracking: 0.36)
        case .title2:     return .init(size: 22, weight: .bold,     leading: 28, tracking: 0.35)
        case .title3:     return .init(size: 20, weight: .semibold, leading: 25, tracking: 0.38)
        case .headline:   return .init(size: 17, weight: .semibold, leading: 22, tracking: -0.43)
        case .body:       return .init(size: 17, weight: .regular,  leading: 22, tracking: -0.43)
        case .callout:    return .init(size: 16, weight: .regular,  leading: 21, tracking: -0.32)
        case .caption:    return .init(size: 13, weight: .regular,  leading: 18, tracking: -0.08)
        }
    }

    /// Соответствие нашей роли — системному `Font.TextStyle`. Используется для
    /// автоматического масштабирования под Dynamic Type.
    public var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title1:     return .title
        case .title2:     return .title2
        case .title3:     return .title3
        case .headline:   return .headline
        case .body:       return .body
        case .callout:    return .callout
        case .caption:    return .caption
        }
    }
}

extension Text {
    /// Применяет AIVibe-роль: системный текст-стиль (с Dynamic Type),
    /// нужный weight и tracking. Цвет НЕ задаётся.
    public func aiType(_ role: AIType) -> some View {
        let s = role.spec
        return self
            .font(.system(role.textStyle, weight: s.weight))
            .tracking(s.tracking)
    }
}

// MARK: - Тень

/// 16/8 soft shadow — для карточек, sheet'ов, плавающих элементов.
/// На iOS реализуется через `.shadow(color:radius:x:y:)`.
public struct AIShadow: ViewModifier {
    public let dark: Bool

    public func body(content: Content) -> some View {
        if dark {
            content
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 8)
                .shadow(color: Color.black.opacity(0.40), radius: 1, x: 0, y: 1)
        } else {
            content
                .shadow(color: Color(hex: 0x1C1916, alpha: 0.08), radius: 8, x: 0, y: 8)
                .shadow(color: Color(hex: 0x1C1916, alpha: 0.04), radius: 1, x: 0, y: 1)
        }
    }
}

extension View {
    /// Стандартная soft-shadow AIVibe.
    public func aiSoftShadow(_ dark: Bool) -> some View {
        modifier(AIShadow(dark: dark))
    }
}

// MARK: - Форматтеры

/// `45 990 ₽` — пробел-разделитель тысяч (ru-RU), знак рубля.
public func aiFmtRub(_ amount: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{00A0}" // неразрывный пробел
    let body = f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    return "\(body)\u{00A0}₽"
}

// MARK: - Color helper

extension Color {
    /// `Color(hex: 0xC2674A)` или `Color(hex: 0xC2674A, alpha: 0.5)`.
    public init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
