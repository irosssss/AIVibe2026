// AIVibe/Features/ARDesigner/ARDesignerComponents.swift
// Building blocks: ARSceneBackground, ARTopBar, ARBudgetBar,
// ARFurnitureSheet, ARApprovalSheet.

import SwiftUI

// MARK: - Симулированная AR-сцена

struct ARSceneBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6D6354), Color(hex: 0x4A4339), Color(hex: 0x2C2820)],
                startPoint: .top, endPoint: .bottom
            )

            // Свет от окна.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xFFE4B4, alpha: 0.25), .clear],
                    center: .center, startRadius: 0, endRadius: 130
                ))
                .frame(width: 260, height: 260)
                .blur(radius: 20)
                .offset(x: -60, y: -200)

            GeometryReader { geo in
                Canvas { ctx, _ in
                    let W = geo.size.width
                    let H = geo.size.height

                    // Пол — параллельные линии.
                    var floor = Path()
                    for i in 0..<12 {
                        let y = H * 0.58 + CGFloat(i) * 30
                        floor.move(to: CGPoint(x: 0, y: y))
                        floor.addLine(to: CGPoint(x: W, y: y))
                    }
                    ctx.stroke(floor, with: .color(.white.opacity(0.05)), lineWidth: 1)

                    // Углы стен.
                    var walls = Path()
                    walls.move(to: CGPoint(x: 30, y: H * 0.23))
                    walls.addLine(to: CGPoint(x: 30, y: H * 0.7))
                    walls.move(to: CGPoint(x: W - 30, y: H * 0.23))
                    walls.addLine(to: CGPoint(x: W - 30, y: H * 0.7))
                    walls.move(to: CGPoint(x: 30, y: H * 0.23))
                    walls.addLine(to: CGPoint(x: W - 30, y: H * 0.23))
                    ctx.stroke(walls, with: .color(.black.opacity(0.18)), lineWidth: 1.5)

                    // AR-диван (terracotta outline + полупрозрачная заливка).
                    var sofa = Path()
                    let baseY = H * 0.66
                    let topY = H * 0.58
                    sofa.move(to: CGPoint(x: 40, y: baseY))
                    sofa.addLine(to: CGPoint(x: 40, y: topY))
                    sofa.addLine(to: CGPoint(x: 260, y: topY))
                    sofa.addLine(to: CGPoint(x: 260, y: baseY))
                    sofa.closeSubpath()
                    ctx.fill(sofa, with: .color(Color(hex: 0xD8C9AA, alpha: 0.55)))
                    ctx.stroke(sofa, with: .color(Color(hex: 0xD17F62, alpha: 0.95)), lineWidth: 2)

                    // Стол (эллипс).
                    let tableRect = CGRect(x: W / 2 - 80, y: H * 0.78 - 12, width: 160, height: 36)
                    ctx.fill(Path(ellipseIn: tableRect), with: .color(Color(hex: 0xD6B589, alpha: 0.55)))
                    ctx.stroke(Path(ellipseIn: tableRect), with: .color(Color(hex: 0xD17F62, alpha: 0.9)), lineWidth: 2)

                    // Кресло (sage).
                    var chair = Path()
                    chair.move(to: CGPoint(x: W - 100, y: H * 0.66))
                    chair.addLine(to: CGPoint(x: W - 100, y: H * 0.58))
                    chair.addLine(to: CGPoint(x: W - 40, y: H * 0.58))
                    chair.addLine(to: CGPoint(x: W - 40, y: H * 0.66))
                    chair.closeSubpath()
                    ctx.fill(chair, with: .color(Color(hex: 0x9CB497, alpha: 0.45)))
                    ctx.stroke(chair, with: .color(Color(hex: 0x9CB497, alpha: 0.95)), lineWidth: 2)

                    // Торшер.
                    var lampStem = Path()
                    lampStem.move(to: CGPoint(x: W - 60, y: H * 0.32))
                    lampStem.addLine(to: CGPoint(x: W - 60, y: H * 0.66))
                    ctx.stroke(lampStem, with: .color(Color(hex: 0xD17F62, alpha: 0.85)), lineWidth: 1.6)
                    let bulbRect = CGRect(x: W - 60 - 22, y: H * 0.32 - 14, width: 44, height: 28)
                    ctx.fill(Path(ellipseIn: bulbRect), with: .color(Color(hex: 0xEFE0C2, alpha: 0.65)))
                    ctx.stroke(Path(ellipseIn: bulbRect), with: .color(Color(hex: 0xD17F62, alpha: 0.9)), lineWidth: 2)

                    // Selection indicator (диван).
                    var sel = Path()
                    sel.addRoundedRect(
                        in: CGRect(x: 22, y: topY - 8, width: 256, height: baseY - topY + 18),
                        cornerSize: CGSize(width: 2, height: 2)
                    )
                    ctx.stroke(sel,
                               with: .color(.white.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
    }
}

// MARK: - Top bar (glass buttons)

struct ARTopBar: View {
    let title: String
    let onClose: () -> Void
    let onSwap: () -> Void

    var body: some View {
        HStack {
            glassButton(icon: "xmark", action: onClose)
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            Spacer()
            glassButton(icon: "arrow.left.arrow.right", action: onSwap)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func glassButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.45))
                    .background(.ultraThinMaterial, in: Circle())
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Budget bar

struct ARBudgetBar: View {
    let total: Int
    let max: Int
    let ratio: Double

    private var barColor: Color {
        if ratio < 0.8 { return Color(hex: 0x9CB497) }   // sage
        if ratio < 1.0 { return Color(hex: 0xE5AC5F) }   // amber
        return Color(hex: 0xC2624A)                      // danger
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 16))
                .foregroundStyle(barColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(aiFmtRub(total)) · из \(aiFmtRub(max))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(barColor)
                            .frame(width: geo.size.width * Swift.min(Swift.max(ratio, 0), 1))
                    }
                }
                .frame(height: 4)
            }
            Text("\(Int(ratio * 100))%")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Bottom furniture sheet

struct ARFurnitureSheet: View {
    let items: [ARFurnitureItem]
    let mode: ARSheetMode
    let total: Int
    let onToggle: () -> Void
    let onRemove: (ARFurnitureItem.ID) -> Void
    let onCheckout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle (tap → toggle).
            Button(action: onToggle) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Header row.
            HStack(alignment: .firstTextBaseline) {
                Text("В подборке · \(items.count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(aiFmtRub(total))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if mode == .expanded {
                expandedList
            } else {
                collapsedCarousel
            }
        }
        .padding(.bottom, 20)
        .background(
            Color(hex: 0x1F1C17, alpha: 0.88),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .background(
            .ultraThinMaterial,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
    }

    // Collapsed: горизонтальный список карточек.
    private var collapsedCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { it in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            PhotoSlot(tone: it.tone, cornerRadius: 10, aspectRatio: 4.0/3.0)
                            MarketBadge(it.market).padding(6)
                        }
                        Text(it.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(minHeight: 32, alignment: .topLeading)
                        Text(aiFmtRub(it.price))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(8)
                    .frame(width: 154)
                    .background(Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 220)
    }

    // Expanded: вертикальный список + итого + CTA.
    private var expandedList: some View {
        VStack(spacing: 8) {
            ForEach(items) { it in
                HStack(spacing: 12) {
                    PhotoSlot(tone: it.tone, cornerRadius: 10, aspectRatio: 1)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            MarketBadge(it.market)
                            Text(it.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Text(it.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(aiFmtRub(it.price))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onRemove(it.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack {
                Text("Итого")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Spacer()
                Text(aiFmtRub(total))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onCheckout) {
                Text("Добавить в корзину")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: 0xD17F62),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

// MARK: - Approval sheet

struct ARApprovalSheet: View {
    let items: [ARFurnitureItem]
    let total: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let delivery = 590

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("ПОДТВЕРЖДЕНИЕ ПЕРЕД ОПЛАТОЙ")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: 0xD17F62))
                Text("\(items.count) товара в Ozon")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("После подтверждения откроется приложение Ozon с готовой корзиной.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 8) {
                ForEach(items) { it in
                    HStack(spacing: 12) {
                        PhotoSlot(tone: it.tone, cornerRadius: 8, aspectRatio: 1)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.title)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                            Text(it.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text(aiFmtRub(it.price))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Divider().overlay(Color.white.opacity(0.10))
                .padding(.top, 12)

            VStack(spacing: 6) {
                HStack {
                    Text("Товары").foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(aiFmtRub(total)).foregroundStyle(.white)
                }
                HStack {
                    Text("Доставка").foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("от \(aiFmtRub(delivery))").foregroundStyle(.white)
                }
                HStack {
                    Text("Итого")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(aiFmtRub(total + delivery))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 8) {
                Button(action: onConfirm) {
                    Text("Подтвердить · открыть Ozon")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: 0xD17F62),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color(hex: 0x1F1C17))
    }
}
