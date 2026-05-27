// AIVibe/DesignSystem/Skeleton.swift
// Placeholder-шиммер для async-загрузки. Использовать вместо спиннеров
// везде, где данные приходят >300 мс (HIG-рекомендация).
//
// Использование:
//   if isLoading {
//       SkeletonBox(cornerRadius: 14).frame(height: 80)
//   } else {
//       Text(data)
//   }
//
// Либо как модификатор:
//   Text(data).redacted(reason: .placeholder).aiShimmering(active: isLoading)

import SwiftUI

// MARK: - SkeletonBox — готовый прямоугольник

public struct SkeletonBox: View {
    public let cornerRadius: CGFloat

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseColor)
            .aiShimmering(active: true)
    }

    private var baseColor: Color {
        scheme == .dark
            ? Color(hex: 0xF1ECE2, alpha: 0.06)
            : Color(hex: 0x1C1916, alpha: 0.05)
    }
}

// MARK: - Shimmer modifier

extension View {
    /// Накладывает движущийся световой блик. Дешёвая анимация — `linearGradient`
    /// двигается по offset.
    public func aiShimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

private struct ShimmerModifier: ViewModifier {
    let active: Bool

    @State private var phase: CGFloat = -1
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if !active {
            content
        } else {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: highlight.opacity(0),    location: 0),
                                .init(color: highlight.opacity(0.7),  location: 0.5),
                                .init(color: highlight.opacity(0),    location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.plusLighter)
                    }
                )
                .mask(content)
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.4).repeatForever(autoreverses: false)
                    ) { phase = 1 }
                }
                .accessibilityHidden(true)
        }
    }

    private var highlight: Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white
    }
}

// MARK: - Композитные placeholder'ы

/// Скелет карточки товара (для каталога / inline furniture).
public struct SkeletonFurnitureCard: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            SkeletonBox(cornerRadius: 10)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            SkeletonBox(cornerRadius: 4).frame(height: 12)
            SkeletonBox(cornerRadius: 4).frame(width: 100, height: 14)
        }
        .padding(10)
        .frame(width: 180)
    }
}

/// Скелет AI-бабла — пока ответ загружается.
public struct SkeletonAIBubble: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBox(cornerRadius: 6).frame(height: 14)
            SkeletonBox(cornerRadius: 6).frame(height: 14)
            SkeletonBox(cornerRadius: 6).frame(width: 180, height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 280, alignment: .leading)
    }
}

#Preview {
    AIThemeReader {
        VStack(spacing: 16) {
            SkeletonBox(cornerRadius: 16).frame(height: 80)
            SkeletonFurnitureCard()
            SkeletonAIBubble()
        }
        .padding()
        .background(AIColors.light.bg)
    }
}
