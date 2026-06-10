// AIVibe/Features/RoomScan/ManualRoomEntryView.swift
// Экран ручного ввода размеров комнаты — путь без LiDAR (массовый рынок РФ).
// Стиль — AIVibe DesignSystem (как RoomScanFlowView). См. docs/UPGRADE_PLAN.md — Фаза 1, A1.

import ComposableArchitecture
import SwiftUI

struct ManualRoomEntryView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Field?

    @State private var widthText = ""
    @State private var depthText = ""
    @State private var heightText = "2.7"

    private enum Field: Hashable { case width, depth, height }

    private var width: Double? { Self.parse(widthText) }
    private var depth: Double? { Self.parse(depthText) }
    private var height: Double? { Self.parse(heightText) }

    private var area: Double? {
        guard let w = width, let d = depth else { return nil }
        return w * d
    }

    private var isValid: Bool {
        guard let w = width, let d = depth, let h = height else { return false }
        return RoomGeometry.isValidManualRoom(widthM: w, depthM: d, heightM: h)
    }

    var body: some View {
        ZStack(alignment: .top) {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        title
                        fields
                        if let area { areaPreview(area) }
                        if let err = store.manualEntryError { errorBanner(err) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton("Продолжить") {
                    guard let w = width, let d = depth, let h = height else { return }
                    Haptics.medium()
                    focused = nil
                    store.send(.manualDimensionsSubmitted(widthM: w, depthM: d, heightM: h))
                }
                .opacity(isValid ? 1 : 0.5)
                .disabled(!isValid)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(c.bg)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focused = nil }
            }
        }
        .onAppear { focused = .width }
    }

    // MARK: - Подвиды

    private var header: some View {
        HStack {
            Button {
                Haptics.light()
                store.send(.backFromManualEntryTapped)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(c.onSurfaceMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Размеры комнаты")
                .aiType(.title1)
                .foregroundStyle(c.onSurface)
            Text("Введите размеры вручную — без сканирования. Подойдёт для любого iPhone.")
                .aiType(.body)
                .foregroundStyle(c.onSurfaceMuted)
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            dimensionField(title: "Ширина", text: $widthText, field: .width)
            dimensionField(title: "Глубина", text: $depthText, field: .depth)
            dimensionField(title: "Высота потолка", text: $heightText, field: .height)
        }
    }

    private func dimensionField(title: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .aiType(.body)
                .foregroundStyle(c.onSurface)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: field)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(c.onSurface)
                .frame(width: 80)
            Text("м")
                .aiType(.callout)
                .foregroundStyle(c.onSurfaceMuted)
        }
        .padding(14)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .aiSoftShadow(scheme == .dark)
    }

    private func areaPreview(_ area: Double) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(c.sandSoft)
                Image(systemName: "ruler")
                    .font(.system(size: 18))
                    .foregroundStyle(c.terracotta)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Площадь")
                    .aiType(.caption)
                    .foregroundStyle(c.onSurfaceMuted)
                Text(String(format: "%.1f м²", area))
                    .aiType(.headline)
                    .foregroundStyle(c.onSurface)
            }
            Spacer()
            if area < RoomGeometry.ManualBounds.minArea {
                Text("мин. 4 м²")
                    .aiType(.caption)
                    .foregroundStyle(c.terracotta)
            }
        }
        .padding(14)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .aiType(.callout)
            .foregroundStyle(c.terracotta)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(c.sandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Парсинг

    /// Принимает "3.5" и "3,5", обрезает пробелы. Возвращает nil для пустого/невалидного.
    private static func parse(_ s: String) -> Double? {
        let normalized = s
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, let value = Double(normalized) else { return nil }
        return value
    }
}
