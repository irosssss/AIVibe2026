// AIVibe/Features/AIAdvisor/AIAdvisorChatComponents.swift
// Кирпичики чата: TopBar, Composer, бабблы, ApprovalCard, InlineFurniture,
// FallbackBanner, SuggestionRow.

import SwiftUI

// MARK: - TopBar

struct ChatTopBar: View {
    let skill: String
    let thinking: Bool

    @Environment(\.aiColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {} label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(c.terracotta)
                }
                .buttonStyle(.plain)
                .frame(width: 40, alignment: .leading)

                Spacer()

                VStack(spacing: 1) {
                    Text("AI-помощник")
                        .aiType(.headline)
                        .foregroundStyle(c.onSurface)
                    Text(skill)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(c.onSurfaceMuted)
                }

                Spacer()

                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(c.onSurfaceMuted)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if thinking {
                ThinkingProgressBar()
                    .frame(height: 2)
            } else {
                Divider().overlay(c.hairline)
            }
        }
        .background(.ultraThinMaterial)
    }
}

private struct ThinkingProgressBar: View {

    @State private var phase: CGFloat = -0.4
    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(c.terracotta)
                .frame(width: geo.size.width * 0.4)
                .offset(x: phase * geo.size.width)
                .clipped()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
        .background(scheme == .dark
                    ? Color(hex: 0xF1ECE2, alpha: 0.06)
                    : Color(hex: 0x1C1916, alpha: 0.05))
    }
}

// MARK: - Composer

struct Composer: View {

    @Binding var text: String
    let onSend: () -> Void
    let onAttach: () -> Void
    let budget: BudgetSnapshot?

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let budget {
                budgetBar(budget)
                    .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    ZStack {
                        Circle().fill(scheme == .dark
                                      ? Color(hex: 0xF1ECE2, alpha: 0.08)
                                      : Color(hex: 0x1C1916, alpha: 0.06))
                        Image(systemName: "paperclip")
                            .font(.system(size: 17))
                            .foregroundStyle(c.onSurfaceMuted)
                    }
                    .frame(width: 36, height: 36)
                    // Hit-area 44×44 (HIG): визуально 36, тап-зона больше.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Прикрепить фото")

                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Опишите вашу идею...")
                            .aiType(.body)
                            .foregroundStyle(c.onSurfaceMuted)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .focused($focused)
                        .font(.system(size: 17, weight: .regular))
                        .tracking(-0.43)
                        .foregroundStyle(c.onSurface)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .lineLimit(1...5)
                }
                .background(c.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(c.divider, lineWidth: 0.5)
                )

                Button {
                    Haptics.light()
                    onSend()
                } label: {
                    ZStack {
                        Circle().fill(c.terracotta)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .opacity(text.isEmpty ? 0.55 : 1)
                .accessibilityLabel("Отправить сообщение")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(c.hairline)
        }
    }

    private func budgetBar(_ b: BudgetSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 16))
                .foregroundStyle(c.sage)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(aiFmtRub(b.current)) · из \(aiFmtRub(b.max))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.onSurface)
                AIProgressBar(value: b.ratio, height: 4)
            }
            Text("\(Int(b.ratio * 100))%")
                .aiType(.caption)
                .foregroundStyle(c.onSurfaceMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .aiSoftShadow(scheme == .dark)
    }
}

// MARK: - Bubbles

struct UserBubble: View {
    let text: String
    @Environment(\.aiColors) private var c

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .aiType(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    c.terracotta,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 18,
                        style: .continuous
                    )
                )
        }
        .padding(.horizontal, 16)
    }
}

struct AIBubble: View {
    let text: String
    let provider: String?
    let streaming: Bool

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(text)
                    .aiType(.body)
                    .foregroundStyle(c.onSurface)
                if streaming {
                    BlinkingCaret(color: c.onSurface)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                c.surface,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .strokeBorder(scheme == .dark ? c.hairline : .clear, lineWidth: 0.5)
            )

            if let provider {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(c.onSurfaceFaint)
                    Text(provider)
                        .font(.system(size: 11))
                        .foregroundStyle(c.onSurfaceFaint)
                }
                .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 56)   // не упирается в правый край
        .padding(.horizontal, 16)
    }
}

// MARK: - InlineFurniture

struct InlineFurnitureRow: View {
    let items: [ChatFurnitureItem]
    let onItemTap: (ChatFurnitureItem) -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { it in
                    Button {
                        Haptics.selection()
                        onItemTap(it)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                PhotoSlot(tone: it.tone, cornerRadius: 10, aspectRatio: 4.0/3.0)
                                MarketBadge(it.market).padding(6)
                            }

                            Text(it.title)
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(c.onSurface)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(aiFmtRub(it.price))
                                .aiType(.headline)
                                .foregroundStyle(c.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .frame(width: 180)
                        .background(c.surface,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .aiSoftShadow(scheme == .dark)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(it.title), \(aiFmtRub(it.price))")
                    .accessibilityHint("Откроет карточку товара")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - ToolCallIndicator

/// Визуальный индикатор tool-вызова: «AI работает, не висит».
/// Появляется в потоке между сообщениями, показывает что именно делает агент.
public struct ToolCallIndicator: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        case searching          // 🔍 Ищу в каталоге
        case analyzingRoom      // 📐 Анализирую комнату
        case generatingPreview  // 🎨 Создаю превью
        case checkingBudget     // 💰 Проверяю бюджет
        case matchingFurniture  // 🪑 Подбираю мебель
    }

    public let id = UUID()
    public let kind: Kind
    public let detail: String   // "Гостиная 18 м²" / "до 50 000 ₽" / etc

    public init(kind: Kind, detail: String) {
        self.kind = kind
        self.detail = detail
    }
}

extension ToolCallIndicator.Kind {
    var icon: String {
        switch self {
        case .searching:         return "magnifyingglass"
        case .analyzingRoom:     return "ruler"
        case .generatingPreview: return "sparkles"
        case .checkingBudget:    return "wallet.pass"
        case .matchingFurniture: return "cube"
        }
    }
    var label: String {
        switch self {
        case .searching:         return "Ищу в каталоге"
        case .analyzingRoom:     return "Анализирую комнату"
        case .generatingPreview: return "Создаю превью"
        case .checkingBudget:    return "Проверяю бюджет"
        case .matchingFurniture: return "Подбираю мебель"
        }
    }
}

struct ToolCallRow: View {
    let call: ToolCallIndicator

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(c.sandSoft)
                Image(systemName: call.kind.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.terracotta)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            }
            .frame(width: 22, height: 22)

            Text(call.kind.label)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(c.onSurface)

            if !call.detail.isEmpty {
                Text("·")
                    .font(.system(.footnote))
                    .foregroundStyle(c.onSurfaceFaint)
                Text(call.detail)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(c.onSurfaceMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (scheme == .dark
                ? Color(hex: 0xF1ECE2, alpha: 0.05)
                : Color(hex: 0x1C1916, alpha: 0.03)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(c.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(call.kind.label), \(call.detail)")
    }
}

// MARK: - BlinkingCaret (для streaming-ответа AI)

struct BlinkingCaret: View {
    let color: Color

    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 9, height: 18)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - ApprovalCard

struct ApprovalCard: View {
    let approval: PendingApproval
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(c.sandSoft)
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(c.terracotta)
                }
                .frame(width: 24, height: 24)
                Text(approval.title)
                    .aiType(.headline)
                    .foregroundStyle(c.onSurface)
            }
            .padding(.bottom, 8)

            Text(approval.detail)
                .aiType(.callout)
                .foregroundStyle(c.onSurfaceMuted)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("Отменить")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.onSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            scheme == .dark
                                ? Color(hex: 0xF1ECE2, alpha: 0.08)
                                : Color(hex: 0x1C1916, alpha: 0.05),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Подтвердить")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(c.terracotta, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(c.sandSoft, lineWidth: 1)
        )
        .aiSoftShadow(scheme == .dark)
        .padding(.horizontal, 16)
    }
}

// MARK: - FallbackBanner

struct FallbackBanner: View {
    let provider: String

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12))
                .foregroundStyle(c.amber)
            (Text("Основной провайдер недоступен — переключился на ")
             + Text(provider).font(.system(size: 13, design: .monospaced)))
                .aiType(.caption)
                .foregroundStyle(c.onSurface)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (scheme == .dark
                ? Color(hex: 0xE5AC5F, alpha: 0.12)
                : Color(hex: 0xDD9F4A, alpha: 0.10)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    (scheme == .dark
                        ? Color(hex: 0xE5AC5F, alpha: 0.30)
                        : Color(hex: 0xDD9F4A, alpha: 0.35)),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - SuggestionRow

struct SuggestionRow: View {
    let suggestion: ChatSuggestion
    let action: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(c.sandSoft)
                    Image(systemName: suggestion.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.terracotta)
                }
                .frame(width: 28, height: 28)

                Text(suggestion.text)
                    .aiType(.body)
                    .foregroundStyle(c.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.onSurfaceFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .aiSoftShadow(scheme == .dark)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BeforeAfterSlider (До/После AI-дизайн)

/// Интерактивный слайдер сравнения «до» и «после» AI-редизайна.
/// Пользователь тянет разделитель — левая сторона показывает оригинал,
/// правая — результат AI.
struct BeforeAfterSlider: View {
    let beforeTone: AIPhotoTone
    let afterTone: AIPhotoTone

    @State private var splitRatio: CGFloat = 0.5
    @Environment(\.aiColors) private var c

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Слой «до» — полная ширина.
                PhotoSlot(tone: beforeTone, cornerRadius: 0, aspectRatio: nil)
                    .frame(width: geo.size.width, height: geo.size.height)

                // Слой «после» — маскируется до splitRatio.
                PhotoSlot(tone: afterTone, cornerRadius: 0, aspectRatio: nil)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask(
                        Rectangle()
                            .frame(width: geo.size.width * splitRatio)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                // Вертикальная линия разделителя.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: geo.size.height)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 0)
                    .offset(x: geo.size.width * splitRatio - 1)

                // Ручка перетаскивания.
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(c.terracotta)
                }
                .position(x: geo.size.width * splitRatio, y: geo.size.height / 2)

                // Метки «До» и «После AI».
                VStack {
                    HStack {
                        Text("До")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.42), in: Capsule())
                            .padding(.leading, 10)
                            .padding(.top, 10)
                        Spacer()
                        Text("После AI")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(c.terracotta.opacity(0.85), in: Capsule())
                            .padding(.trailing, 10)
                            .padding(.top, 10)
                    }
                    Spacer()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = value.location.x / max(geo.size.width, 1)
                        splitRatio = min(0.95, max(0.05, ratio))
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Сравнение до и после AI-дизайна. Потяните разделитель для сравнения.")
        .accessibilityHint("Смахните влево или вправо для перемещения разделителя")
    }
}
