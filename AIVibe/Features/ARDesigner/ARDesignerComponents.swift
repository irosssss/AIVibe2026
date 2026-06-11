// AIVibe/Features/ARDesigner/ARDesignerComponents.swift
// Building blocks: ARTopBar, ARBudgetBar, ARFurnitureSheet, ARApprovalSheet.

import ComposableArchitecture
import SwiftUI

// MARK: - Маппинг FurnitureItem → UI

/// Русское имя типа мебели («sofa» → «Диван»).
func furnitureTypeDisplayName(_ itemType: String) -> String {
    let names: [String: String] = [
        "sofa": "Диван", "диван": "Диван",
        "table": "Стол", "стол": "Стол",
        "chair": "Стул", "стул": "Стул",
        "armchair": "Кресло", "кресло": "Кресло",
        "bed": "Кровать", "кровать": "Кровать",
        "wardrobe": "Шкаф", "шкаф": "Шкаф",
        "shelf": "Полка", "bookshelf": "Полка", "полка": "Полка",
        "cabinet": "Тумба", "тумба": "Тумба",
        "lamp": "Торшер", "торшер": "Торшер",
        "carpet": "Ковёр", "ковёр": "Ковёр",
        "desk": "Письменный стол"
    ]
    return names[itemType.lowercased()] ?? itemType
}

func furnitureDisplayTitle(_ item: FurnitureItem) -> String {
    let displayType = furnitureTypeDisplayName(item.itemType)
    if item.brand.isEmpty { return displayType }
    // Полное название из каталога (B4) уже начинается с типа
    // («Диван трёхместный …») — не дублируем «Диван Диван …».
    if item.brand.lowercased().hasPrefix(displayType.lowercased()) {
        return item.brand
    }
    return "\(displayType) \(item.brand)"
}

func furnitureSubtitle(_ item: FurnitureItem) -> String {
    let w = Int(item.size.x * 100)
    let d = Int(item.size.z * 100)
    let h = Int(item.size.y * 100)
    var parts: [String] = ["\(w)×\(d)×\(h) см"]
    if !item.article.isEmpty { parts.append(item.article) }
    return parts.joined(separator: " · ")
}

func furnitureTone(for itemType: String) -> AIPhotoTone {
    switch itemType.lowercased() {
    case "sofa", "диван": return .sand
    case "table", "стол", "desk": return .taupe
    case "chair", "стул": return .stone
    case "armchair", "кресло": return .sage
    case "bed", "кровать": return .cream
    case "wardrobe", "шкаф", "bookshelf", "полка": return .clay
    case "lamp", "торшер": return .olive
    default: return .terracotta
    }
}

func furnitureIcon(_ itemType: String) -> String {
    switch itemType.lowercased() {
    case "sofa", "диван": return "sofa"
    case "table", "стол": return "table.furniture"
    case "chair", "стул": return "chair"
    case "armchair", "кресло": return "chair.lounge"
    case "bed", "кровать": return "bed.double"
    case "wardrobe", "шкаф": return "cabinet"
    case "bookshelf", "полка": return "books.vertical"
    case "lamp", "торшер": return "lamp.floor"
    case "desk", "письменный стол": return "desktopcomputer"
    default: return "cube"
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
        if ratio < 0.8 { return Color(hex: 0x9CB497) }
        if ratio < 1.0 { return Color(hex: 0xE5AC5F) }
        return Color(hex: 0xC2624A)
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
    let items: IdentifiedArrayOf<FurnitureItem>
    let prices: [FurnitureItem.ID: Int]
    let selectedID: FurnitureItem.ID?
    let mode: ARSheetMode
    let total: Int
    let isRefining: Bool
    let onToggle: () -> Void
    let onSelect: (FurnitureItem.ID) -> Void
    let onRemove: (FurnitureItem.ID) -> Void
    let onRefine: () -> Void
    let onCheckout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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

            HStack(alignment: .firstTextBaseline) {
                Text("В подборке · \(items.count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if total > 0 {
                    Text(aiFmtRub(total))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                }
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

    private var collapsedCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    let isSelected = item.id == selectedID
                    Button { onSelect(item.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PhotoSlot(
                                tone: furnitureTone(for: item.itemType),
                                label: furnitureIcon(item.itemType),
                                cornerRadius: 10,
                                aspectRatio: 4.0 / 3.0
                            )
                            Text(furnitureDisplayTitle(item))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .frame(minHeight: 32, alignment: .topLeading)
                            if let price = prices[item.id] {
                                Text(aiFmtRub(price))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("Цена уточняется")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(8)
                        .frame(width: 154)
                        .background(
                            Color.white.opacity(isSelected ? 0.14 : 0.06),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            isSelected
                                ? RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(hex: 0xD17F62), lineWidth: 1.5)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 220)
    }

    /// Сколько строк помещается без скролла; больше — список скроллится,
    /// чтобы развёрнутая шторка не вылезала за экран и не наезжала на топ-бар.
    private static let expandedRowsWithoutScroll = 4

    private var expandedList: some View {
        VStack(spacing: 8) {
            if items.count > Self.expandedRowsWithoutScroll {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) { expandedRows }
                }
                .frame(height: 312)
            } else {
                expandedRows
            }

            if total > 0 {
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
            }

            HStack(spacing: 8) {
                Button(action: onRefine) {
                    HStack(spacing: 6) {
                        if isRefining {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Уточнить")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRefining)

                Button(action: onCheckout) {
                    Text("В корзину")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color(hex: 0xD17F62),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var expandedRows: some View {
        ForEach(items) { item in
            let isSelected = item.id == selectedID
            HStack(spacing: 12) {
                PhotoSlot(
                    tone: furnitureTone(for: item.itemType),
                    cornerRadius: 10,
                    aspectRatio: 1
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(furnitureSubtitle(item))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(furnitureDisplayTitle(item))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    if let price = prices[item.id] {
                        Text(aiFmtRub(price))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { onRemove(item.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                Color.white.opacity(isSelected ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .onTapGesture { onSelect(item.id) }
        }
    }
}

// MARK: - Approval sheet

struct ARApprovalSheet: View {
    let items: IdentifiedArrayOf<FurnitureItem>
    let prices: [FurnitureItem.ID: Int]
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
                Text("\(items.count) товаров")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("После подтверждения откроется приложение маркетплейса с готовой корзиной.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        PhotoSlot(
                            tone: furnitureTone(for: item.itemType),
                            cornerRadius: 8,
                            aspectRatio: 1
                        )
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(furnitureDisplayTitle(item))
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                            Text(furnitureSubtitle(item))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if let price = prices[item.id] {
                            Text(aiFmtRub(price))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
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
                if total > 0 {
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
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 8) {
                Button(action: onConfirm) {
                    Text("Подтвердить · открыть маркетплейс")
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
