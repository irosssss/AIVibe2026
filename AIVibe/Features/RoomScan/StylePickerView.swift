// AIVibe/Features/RoomScan/StylePickerView.swift
// Экран выбора стиля, бюджета и пожеланий перед генерацией дизайна.

import ComposableArchitecture
import SwiftUI

struct StylePickerView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    @State private var selectedStyle: DesignStyle = .scandinavian
    @State private var budgetMin: Double = 30_000
    @State private var budgetMax: Double = 200_000
    @State private var hasBudget: Bool = false
    @State private var additionalText: String = ""

    var body: some View {
        ZStack {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        Haptics.light()
                        store.send(.backFromStyleTapped)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(c.terracotta)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Стиль дизайна")
                        .aiType(.headline)
                        .foregroundStyle(c.onSurface)
                    Spacer()
                    Color.clear.frame(width: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Стили
                        CapsLabel("Выберите стиль")
                            .padding(.leading, 4)

                        styleGrid

                        // Бюджет
                        CapsLabel("Бюджет")
                            .padding(.leading, 4)
                            .padding(.top, 4)

                        budgetSection

                        // Пожелания
                        CapsLabel("Дополнительно")
                            .padding(.leading, 4)
                            .padding(.top, 4)

                        TextField("Например: нужен рабочий стол у окна", text: $additionalText, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(.body))
                            .padding(14)
                            .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .aiSoftShadow(scheme == .dark)

                        // Ошибка (если была)
                        if let error = store.designError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .aiType(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton("Создать дизайн") {
                    Haptics.medium()
                    let prefs = UserDesignPreferences(
                        style: selectedStyle,
                        budgetMin: hasBudget ? Int(budgetMin) : nil,
                        budgetMax: hasBudget ? Int(budgetMax) : nil,
                        restrictions: [],
                        additionalText: additionalText.isEmpty ? nil : additionalText
                    )
                    store.send(.preferencesSet(prefs))
                    store.send(.generateDesignTapped)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().overlay(c.hairline)
                }
            }
        }
    }

    // MARK: - Сетка стилей

    private var styleGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            ForEach(DesignStyle.allCases, id: \.self) { style in
                styleCard(style)
            }
        }
    }

    private func styleCard(_ style: DesignStyle) -> some View {
        let isSelected = selectedStyle == style
        return Button {
            Haptics.selection()
            selectedStyle = style
        } label: {
            VStack(spacing: 6) {
                Text(style.emoji)
                    .font(.system(size: 28))
                Text(style.displayName)
                    .aiType(.body)
                    .foregroundStyle(isSelected ? c.terracotta : c.onSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected ? c.terracotta.opacity(0.08) : c.surface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? c.terracotta : .clear, lineWidth: 2)
            )
            .aiSoftShadow(scheme == .dark)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Бюджет

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasBudget) {
                Text("Указать бюджет")
                    .aiType(.body)
                    .foregroundStyle(c.onSurface)
            }
            .tint(c.terracotta)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .aiSoftShadow(scheme == .dark)

            if hasBudget {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("от \(formatted(budgetMin))")
                            .aiType(.caption)
                            .foregroundStyle(c.onSurfaceMuted)
                        Spacer()
                        Text("до \(formatted(budgetMax))")
                            .aiType(.caption)
                            .foregroundStyle(c.onSurfaceMuted)
                    }

                    HStack(spacing: 12) {
                        Slider(value: $budgetMin, in: 10_000...500_000, step: 10_000)
                            .tint(c.terracotta)
                        Slider(value: $budgetMax, in: 10_000...1_000_000, step: 10_000)
                            .tint(c.sage)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .aiSoftShadow(scheme == .dark)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasBudget)
    }

    private func formatted(_ value: Double) -> String {
        let intVal = Int(value)
        if intVal >= 1_000_000 {
            return "\(intVal / 1_000_000) млн ₽"
        } else if intVal >= 1_000 {
            return "\(intVal / 1_000) тыс ₽"
        }
        return "\(intVal) ₽"
    }
}

// MARK: - Экран генерации

struct DesignGeneratingView: View {
    let store: StoreOf<RoomScanFlowFeature>

    @Environment(\.aiColors) private var c
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            c.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 56))
                    .foregroundStyle(c.terracotta)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }

                Text("Создаём дизайн…")
                    .aiType(.title2)
                    .foregroundStyle(c.onSurface)

                Text("AI подбирает мебель и расставляет по комнате")
                    .aiType(.body)
                    .foregroundStyle(c.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                ProgressView()
                    .tint(c.terracotta)
            }
        }
    }
}

// MARK: - Экран результата дизайна

struct DesignCompleteView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>
    let onContinue: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("Ваш дизайн")
                        .aiType(.headline)
                        .foregroundStyle(c.onSurface)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let plan = store.designPlan {
                            // Confidence
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(c.terracotta)
                                Text("Уверенность: \(Int(plan.confidence * 100))%")
                                    .aiType(.body)
                                    .foregroundStyle(c.onSurface)
                                Spacer()
                                Text(plan.providerName)
                                    .aiType(.caption)
                                    .foregroundStyle(c.onSurfaceMuted)
                            }
                            .padding(14)
                            .background(c.surface, in: RoundedRectangle(cornerRadius: 14))
                            .aiSoftShadow(scheme == .dark)

                            // Объяснение
                            if !plan.explanation.isEmpty {
                                Text(plan.explanation)
                                    .aiType(.body)
                                    .foregroundStyle(c.onSurface)
                                    .padding(14)
                                    .background(c.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .aiSoftShadow(scheme == .dark)
                            }

                            // Список мебели
                            CapsLabel("Мебель (\(plan.items.count))")
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(plan.items.enumerated()), id: \.element.id) { i, item in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8).fill(c.sandSoft)
                                            Image(systemName: furnitureIcon(item.itemType))
                                                .font(.system(size: 14))
                                                .foregroundStyle(c.terracotta)
                                        }
                                        .frame(width: 28, height: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.itemType)
                                                .aiType(.body)
                                                .foregroundStyle(c.onSurface)
                                            if !item.brand.isEmpty {
                                                Text(item.brand)
                                                    .aiType(.caption)
                                                    .foregroundStyle(c.onSurfaceMuted)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)

                                    if i < plan.items.count - 1 {
                                        Divider().overlay(c.hairline)
                                            .padding(.leading, 54)
                                    }
                                }
                            }
                            .background(c.surface, in: RoundedRectangle(cornerRadius: 16))
                            .aiSoftShadow(scheme == .dark)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    SecondaryButton("Изменить стиль") {
                        Haptics.light()
                        store.send(.backFromStyleTapped)
                    }
                    PrimaryButton("Смотреть в AR") {
                        Haptics.medium()
                        store.send(.continueTapped)
                        onContinue()
                    }
                    .layoutPriority(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().overlay(c.hairline)
                }
            }
        }
    }

    private func furnitureIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "sofa", "диван":      return "sofa"
        case "table", "стол":      return "table.furniture"
        case "chair", "стул":      return "chair"
        case "bed", "кровать":     return "bed.double"
        case "wardrobe", "шкаф":   return "cabinet"
        case "bookshelf", "полка": return "books.vertical"
        default:                   return "cube"
        }
    }
}
