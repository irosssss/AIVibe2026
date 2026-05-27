// AIVibe/Features/RoomScan/RoomScanFlowView.swift
// Дизайн: docs/design/ai-vibe/project/scan.jsx
// Три экрана flow: intro → scanning (RoomPlan / симуляция) → result.

import ComposableArchitecture
import SwiftUI

#if canImport(RoomPlan)
import RoomPlan
#endif

// MARK: - Flow entry

public struct RoomScanFlowScreen: View {
    private let onClose: () -> Void
    private let onContinueWithResult: () -> Void

    @StateObject private var host = StoreHost<RoomScanFlowFeature>(
        Store(initialState: RoomScanFlowFeature.State()) { RoomScanFlowFeature() }
    )

    public init(
        onClose: @escaping () -> Void = {},
        onContinueWithResult: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.onContinueWithResult = onContinueWithResult
    }

    public var body: some View {
        RoomScanFlowView(
            store: host.store,
            onClose: onClose,
            onContinueWithResult: onContinueWithResult
        )
        .navigationBarBackButtonHidden(true)
    }
}

struct RoomScanFlowView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>
    let onClose: () -> Void
    let onContinueWithResult: () -> Void

    var body: some View {
        AIThemeReader {
            switch store.phase {
            case .intro:    ScanIntroScreenView(store: store, onClose: onClose)
            case .scanning: ScanActiveScreenView(store: store)
            case .result:   ScanResultScreenView(store: store, onContinue: onContinueWithResult)
            }
        }
    }
}

// MARK: - Screen 1: Intro

struct ScanIntroScreenView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>
    let onClose: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    private let tips: [(String, String)] = [
        ("lightbulb", "Хорошее освещение"),
        ("figure.walk", "Двигайтесь медленно"),
        ("viewfinder", "Захватите углы")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
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

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Иллюстрация
                        ScanIntroIllustration()
                            .frame(height: 240)
                            .background(
                                LinearGradient(colors: [c.sandSoft, c.bg],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Отсканируйте комнату")
                                .aiType(.title1)
                                .foregroundStyle(c.onSurface)
                            Text("Медленно пройдитесь по периметру, направляя камеру на стены, окна и мебель. Занимает 2–3 минуты.")
                                .aiType(.body)
                                .foregroundStyle(c.onSurfaceMuted)
                        }

                        VStack(spacing: 12) {
                            ForEach(tips, id: \.0) { icon, text in
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
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    PrimaryButton("Начать сканирование") {
                        Haptics.medium()
                        store.send(.startScanTapped)
                    }
                    Button {
                        Haptics.light()
                        store.send(.manualEntryTapped)
                    } label: {
                        Text("Нет LiDAR? Ввести вручную")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(c.terracotta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(c.bg)
            }
        }
    }
}

// MARK: - Screen 2: Active scan

struct ScanActiveScreenView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>

    /// Observable модель прогресса — обновляется RoomPlan delegate'ом или
    /// симулятор-таймером.
    @State private var progress = RoomScanProgress()

    /// Таймер симулятор-fallback: на устройстве без LiDAR имитирует прогресс
    /// до 100% за ~12 секунд.
    @State private var simulatorTimerCancel: Task<Void, Never>?

    var body: some View {
        ZStack {
            #if canImport(RoomPlan)
            // На реальном устройстве — RoomPlan с real-time delegate.
            RoomCaptureRepresentableV2(
                progress: progress,
                onCapturedRoom: { [store] room in
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("scan_\(UUID().uuidString).usdz")
                    do {
                        try room.export(to: url)
                        let data = try Data(contentsOf: url)
                        try? FileManager.default.removeItem(at: url)
                        Task { @MainActor in store.send(.scanFinished(data)) }
                    } catch {
                        let msg = error.localizedDescription
                        Task { @MainActor in store.send(.scanFailed(msg)) }
                    }
                },
                onError: { [store] error in
                    let msg = error.localizedDescription
                    Task { @MainActor in store.send(.scanFailed(msg)) }
                }
            )
            .ignoresSafeArea()
            #else
            ScanCameraSimulatedBackground()
                .ignoresSafeArea()
            #endif

            ScanActiveOverlay(
                progress: progress,
                onFinish: {
                    Haptics.success()
                    store.send(.scanFinished(Data()))
                }
            )
        }
        .onChange(of: progress.isComplete) { _, complete in
            // Auto-stop при достижении threshold + min surfaces.
            guard complete else { return }
            Haptics.success()
            store.send(.scanFinished(Data()))
        }
        .onAppear {
            #if targetEnvironment(simulator)
            // Симулятор-fallback: имитируем прогресс таймером.
            simulatorTimerCancel = Task { @MainActor in
                let steps = 12
                for i in 1...steps where !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let walls   = min(i / 3, 4)
                    let objects = min(i / 4, 3)
                    let conf    = min(Double(i) / Double(steps), 1.0)
                    progress.update(walls: walls, objects: objects, windows: 1, doors: 1, confidenceHigh: conf)
                    if i == 4 { progress.setInstruction("Поверните к окну") }
                    if i == 8 { progress.setInstruction("Захватите углы комнаты") }
                }
            }
            #endif
        }
        .onDisappear {
            simulatorTimerCancel?.cancel()
        }
    }
}

/// Симулированный камера-фон с детектированной мебелью + feature points —
/// fallback когда RoomPlan недоступен (Simulator).
private struct ScanCameraSimulatedBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x4A463D), Color(hex: 0x2E2A23), Color(hex: 0x1A1814)],
                startPoint: .top, endPoint: .bottom
            )

            RadialGradient(
                colors: [Color(hex: 0x786C5A, alpha: 0.35), .clear],
                center: .init(x: 0.5, y: 0.45),
                startRadius: 0, endRadius: 220
            )

            GeometryReader { geo in
                Canvas { ctx, _ in
                    // Дальние линии пола.
                    let floor = Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height * 0.71))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.71))
                        p.move(to: CGPoint(x: 0, y: geo.size.height * 0.80))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.80))
                        p.move(to: CGPoint(x: 0, y: geo.size.height * 0.89))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.89))
                    }
                    ctx.stroke(floor, with: .color(Color(hex: 0xD17F62, alpha: 0.6)), lineWidth: 1)

                    // Силуэт дивана — sage.
                    let sofa = Path { p in
                        let baseY = geo.size.height * 0.62
                        let topY = geo.size.height * 0.55
                        p.move(to: CGPoint(x: 90, y: baseY))
                        p.addLine(to: CGPoint(x: 90, y: topY))
                        p.addLine(to: CGPoint(x: geo.size.width - 90, y: topY))
                        p.addLine(to: CGPoint(x: geo.size.width - 90, y: baseY))
                        p.closeSubpath()
                    }
                    ctx.stroke(sofa, with: .color(Color(hex: 0x9CB497, alpha: 0.9)),
                               style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Feature-точки.
                    for i in 0..<35 {
                        let x = CGFloat((i * 53) % Int(geo.size.width))
                        let y = CGFloat((i * 71) % Int(geo.size.height * 0.7)) + geo.size.height * 0.22
                        let r: CGFloat = 1 + CGFloat(i % 2)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color.white.opacity(0.7))
                        )
                    }
                }
            }
        }
    }
}

private struct ScanActiveOverlay: View {
    let progress: RoomScanProgress
    let onFinish: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack {
            VStack(spacing: 10) {
                // Прогресс-бар (top).
                ScanProgressBar(value: progress.progress)
                    .frame(maxWidth: 320, maxHeight: 6)

                // Статус-капсула со счётчиками.
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: 0xD17F62))
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 1 : 0.4)
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))

                // Инструкция (если есть).
                if let instruction = progress.instruction {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(instruction)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: 0xDD9F4A, alpha: 0.85),
                                in: Capsule(style: .continuous))
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.top, 16)
            .animation(.easeInOut(duration: 0.25), value: progress.instruction)
            .animation(.easeInOut(duration: 0.3), value: progress.progress)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onFinish) {
                    ZStack {
                        Circle().fill(Color(hex: 0xD17F62))
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 4))
                            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 80, height: 80)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Завершить сканирование")

                Text("Завершить")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// Динамический текст в статус-капсуле в зависимости от прогресса.
    private var statusText: String {
        if progress.wallsCount == 0 {
            return "Ищу стены…"
        }
        let totalObjects = progress.objectsCount + progress.windowsCount + progress.doorsCount
        return "Найдено: \(progress.wallsCount) \(wallsWord(progress.wallsCount)) · \(totalObjects) \(objectsWord(totalObjects))"
    }

    private func wallsWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "стен" }
        if mod10 == 1 { return "стена" }
        if (2...4).contains(mod10) { return "стены" }
        return "стен"
    }
    private func objectsWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "объектов" }
        if mod10 == 1 { return "объект" }
        if (2...4).contains(mod10) { return "объекта" }
        return "объектов"
    }
}

/// Тонкая полоса прогресса для AR-overlay — белая с террактовой заливкой.
private struct ScanProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xD17F62), Color(hex: 0xE5AC5F)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * max(0, min(value, 1)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Покрытие комнаты")
        .accessibilityValue("\(Int(value * 100)) процентов")
    }
}

// MARK: - Screen 3: Result

struct ScanResultScreenView: View {
    @Bindable var store: StoreOf<RoomScanFlowFeature>
    let onContinue: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        store.send(.backFromResultTapped)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(c.terracotta)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Результат")
                        .aiType(.headline)
                        .foregroundStyle(c.onSurface)
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundStyle(c.terracotta)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // 3D wireframe stub
                        Room3DWireframe()
                            .frame(height: 220)
                            .background(
                                LinearGradient(
                                    colors: scheme == .dark
                                        ? [Color(hex: 0x2A2620), Color(hex: 0x1A1814)]
                                        : [c.sandSoft, c.bg],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                HStack(spacing: 4) {
                                    Image(systemName: "cube").font(.system(size: 10))
                                    Text("покрутите").font(.system(size: 13))
                                }
                                .foregroundStyle(c.onSurfaceMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(scheme == .dark
                                            ? Color.black.opacity(0.4)
                                            : Color.white.opacity(0.7),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .padding(10)
                            }
                            .aiSoftShadow(scheme == .dark)

                        // Metrics
                        HStack(spacing: 8) {
                            metricCell("Площадь", store.metrics.area)
                            metricCell("Высота", store.metrics.height)
                            metricCell("Объектов", "\(store.metrics.objectsCount)")
                        }

                        // Objects list
                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel("Обнаружено")
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(store.detectedObjects.enumerated()), id: \.element.id) { i, obj in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8).fill(c.sandSoft)
                                            Image(systemName: obj.icon)
                                                .font(.system(size: 14))
                                                .foregroundStyle(c.terracotta)
                                        }
                                        .frame(width: 28, height: 28)

                                        Text(obj.name)
                                            .aiType(.body)
                                            .foregroundStyle(c.onSurface)
                                        Spacer()
                                        Button {
                                            store.send(.editObjectTapped(obj.id))
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 13))
                                                .foregroundStyle(c.onSurfaceFaint)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)

                                    if i < store.detectedObjects.count - 1 {
                                        Divider().overlay(c.hairline)
                                            .padding(.leading, 14 + 28 + 12)
                                    }
                                }
                            }
                            .background(c.surface,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    SecondaryButton("Пересканировать") {
                        Haptics.warning()
                        store.send(.rescanTapped)
                    }
                    PrimaryButton("Продолжить") {
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

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).aiType(.caption).foregroundStyle(c.onSurfaceMuted)
            Text(value)
                .aiType(.title3)
                .foregroundStyle(c.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .aiSoftShadow(scheme == .dark)
    }
}

// MARK: - Vector helpers

/// Линеарт человека сканирующего комнату (по scan.jsx).
struct ScanIntroIllustration: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 320
            let sy = size.height / 240
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }
            let stroke = scheme == .dark
                ? Color(hex: 0xF1ECE2, alpha: 0.55)
                : Color(hex: 0x1C1916, alpha: 0.55)
            let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)

            // Стены.
            var walls = Path()
            walls.move(to: p(40, 200)); walls.addLine(to: p(100, 150)); walls.addLine(to: p(240, 150)); walls.addLine(to: p(290, 200)); walls.closeSubpath()
            walls.move(to: p(40, 80)); walls.addLine(to: p(100, 110)); walls.addLine(to: p(240, 110)); walls.addLine(to: p(290, 80))
            walls.move(to: p(40, 80)); walls.addLine(to: p(40, 200))
            walls.move(to: p(290, 80)); walls.addLine(to: p(290, 200))
            walls.move(to: p(100, 110)); walls.addLine(to: p(100, 150))
            walls.move(to: p(240, 110)); walls.addLine(to: p(240, 150))
            ctx.stroke(walls, with: .color(stroke), style: style)

            // Окно.
            var window = Path()
            window.addRoundedRect(in: CGRect(x: 125 * sx, y: 120 * sy, width: 30 * sx, height: 22 * sy), cornerSize: CGSize(width: 1, height: 1))
            window.move(to: p(140, 120)); window.addLine(to: p(140, 142))
            window.move(to: p(125, 131)); window.addLine(to: p(155, 131))
            ctx.stroke(window, with: .color(stroke), style: style)

            // Человек.
            var person = Path()
            person.addEllipse(in: CGRect(x: (170 - 6) * sx, y: (156 - 6) * sy, width: 12 * sx, height: 12 * sy))
            person.move(to: p(170, 162)); person.addLine(to: p(170, 188))
            person.move(to: p(170, 170)); person.addLine(to: p(184, 178))
            person.move(to: p(170, 188)); person.addLine(to: p(162, 210))
            person.move(to: p(170, 188)); person.addLine(to: p(178, 210))
            ctx.stroke(person, with: .color(stroke), style: style)

            // Телефон.
            let phoneRect = CGRect(x: 180 * sx, y: 170 * sy, width: 14 * sx, height: 20 * sy)
            ctx.fill(Path(roundedRect: phoneRect, cornerRadius: 2),
                     with: .color(scheme == .dark ? Color(hex: 0x2A2620) : .white))
            ctx.stroke(Path(roundedRect: phoneRect, cornerRadius: 2), with: .color(stroke), style: style)

            // Лучи скана.
            var beams = Path()
            beams.move(to: p(194, 178)); beams.addLine(to: p(230, 130))
            beams.move(to: p(194, 180)); beams.addLine(to: p(235, 140))
            ctx.stroke(beams, with: .color(stroke.opacity(0.6)),
                       style: .init(lineWidth: 1.4, lineCap: .round, dash: [2, 3]))
        }
    }
}

/// 3D-каркас комнаты для экрана Result.
struct Room3DWireframe: View {
    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 360
            let sy = size.height / 220
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }
            let baseStroke = scheme == .dark
                ? Color(hex: 0xF1ECE2, alpha: 0.55)
                : Color(hex: 0x1C1916, alpha: 0.55)
            let line = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)

            // Объём комнаты — terracotta пол + базовые рёбра.
            var floor = Path()
            floor.move(to: p(50, 180)); floor.addLine(to: p(130, 130)); floor.addLine(to: p(290, 130)); floor.addLine(to: p(320, 180)); floor.closeSubpath()
            ctx.stroke(floor, with: .color(c.terracotta),
                       style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            var box = Path()
            box.move(to: p(50, 60)); box.addLine(to: p(130, 80)); box.addLine(to: p(290, 80)); box.addLine(to: p(320, 60))
            box.move(to: p(50, 60)); box.addLine(to: p(50, 180))
            box.move(to: p(320, 60)); box.addLine(to: p(320, 180))
            box.move(to: p(130, 80)); box.addLine(to: p(130, 130))
            box.move(to: p(290, 80)); box.addLine(to: p(290, 130))
            ctx.stroke(box, with: .color(baseStroke), style: line)

            // Окно.
            ctx.stroke(
                Path(CGRect(x: 160 * sx, y: 92 * sy, width: 36 * sx, height: 22 * sy)),
                with: .color(c.sage), style: .init(lineWidth: 1.8)
            )

            // Дверь.
            var door = Path()
            door.move(to: p(260, 100)); door.addLine(to: p(280, 92)); door.addLine(to: p(280, 124)); door.addLine(to: p(260, 130)); door.closeSubpath()
            ctx.stroke(door, with: .color(c.sage), style: .init(lineWidth: 1.8))

            // Диван.
            var sofa = Path()
            sofa.move(to: p(80, 165)); sofa.addLine(to: p(80, 150)); sofa.addLine(to: p(180, 150)); sofa.addLine(to: p(180, 165)); sofa.closeSubpath()
            sofa.move(to: p(80, 150)); sofa.addLine(to: p(70, 142)); sofa.addLine(to: p(70, 160)); sofa.addLine(to: p(80, 165))
            sofa.move(to: p(180, 150)); sofa.addLine(to: p(188, 142)); sofa.addLine(to: p(188, 160)); sofa.addLine(to: p(180, 165))
            ctx.stroke(sofa, with: .color(c.sage), style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            // Стол.
            ctx.stroke(
                Path(ellipseIn: CGRect(x: (230 - 22) * sx, y: (158 - 6) * sy, width: 44 * sx, height: 12 * sy)),
                with: .color(c.sage), style: .init(lineWidth: 1.8)
            )
        }
    }
}
