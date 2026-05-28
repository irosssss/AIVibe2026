// AIVibe/DesignSystem/PhotoSlot.swift
// Тёплый gradient-плейсхолдер фото — точный аналог PhotoSlot из tokens.jsx.
// В проде заменяется на AsyncImage/Kingfisher, но публичный API сохраняется.

import SwiftUI

public enum AIPhotoTone: String, CaseIterable, Sendable {
    case sand, terracotta, sage, taupe, clay, stone, cream, olive

    public var colors: (Color, Color) {
        switch self {
        case .sand:       return (Color(hex: 0xE9D6B0), Color(hex: 0xD9BC85))
        case .terracotta: return (Color(hex: 0xE8C9BC), Color(hex: 0xD89B82))
        case .sage:       return (Color(hex: 0xCFDCC8), Color(hex: 0xA8C0A2))
        case .taupe:      return (Color(hex: 0xD9CDB9), Color(hex: 0xB8A88E))
        case .clay:       return (Color(hex: 0xE0BFA8), Color(hex: 0xC49479))
        case .stone:      return (Color(hex: 0xD5CFC4), Color(hex: 0xA9A294))
        case .cream:      return (Color(hex: 0xF3EAD8), Color(hex: 0xDDCDAF))
        case .olive:      return (Color(hex: 0xC9C7A2), Color(hex: 0x9DA67A))
        }
    }
}

/// Плейсхолдер изображения: тёплый диагональный градиент + диагональная штриховка
/// + опциональная monospace-подпись внизу-слева.
public struct PhotoSlot: View {
    public let tone: AIPhotoTone
    public let label: String?
    public let cornerRadius: CGFloat
    public let aspectRatio: CGFloat?  // ширина/высота; nil = заполняет родителя

    public init(
        tone: AIPhotoTone = .sand,
        label: String? = nil,
        cornerRadius: CGFloat = 14,
        aspectRatio: CGFloat? = 4.0 / 3.0
    ) {
        self.tone = tone
        self.label = label
        self.cornerRadius = cornerRadius
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        let (c1, c2) = tone.colors

        let content = ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [c1, c2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Диагональная штриховка 45° — лёгкий «текстиль».
            StripePattern()
                .foregroundStyle(Color.white.opacity(0.10))

            if let label {
                Text(label.lowercased())
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(Color(hex: 0x281E14, alpha: 0.55))
                    .padding(.leading, 10)
                    .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        if let aspectRatio {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            content
        }
    }
}

/// Повторяющиеся диагональные полосы — `repeating-linear-gradient(45deg, …)` из дизайна.
private struct StripePattern: View {
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 14
            let diag = sqrt(geo.size.width * geo.size.width + geo.size.height * geo.size.height)
            ZStack {
                ForEach(0..<Int(diag / step) + 4, id: \.self) { i in
                    Rectangle()
                        .frame(width: 2, height: diag * 2)
                        .rotationEffect(.degrees(45))
                        .offset(x: CGFloat(i) * step - diag, y: 0)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    AIThemeReader {
        VStack(spacing: 12) {
            PhotoSlot(tone: .sand, label: "ikea")
            PhotoSlot(tone: .sage, label: "hoff")
            PhotoSlot(tone: .terracotta, label: "divan.ru")
        }
        .padding()
        .background(AIColors.light.bg)
    }
}
