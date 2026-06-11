// AIVibe/Features/ARDesigner/ARDesignerView.swift
// RealityKit AR-сцена с жестами + glass-UI overlay.

import ComposableArchitecture
import RealityKit
import SwiftUI

// MARK: - Public entry

public struct ARDesignerScreen: View {
    private let onClose: () -> Void

    /// One-time store creation через StoreHost — Store, созданный прямо в
    /// `body`, пересоздавался при каждом re-render родителя и сбрасывал
    /// всё состояние AR (подборку, выбор, шторку). Новый план → новый
    /// экран через `.id(plan.id)` на стороне вызывающего.
    @StateObject private var host: StoreHost<ARDesignerFeature>

    public init(
        designPlan: RoomDesignPlan,
        roomGeometry: RoomGeometry,
        onClose: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        _host = StateObject(wrappedValue: StoreHost(
            Store(
                initialState: ARDesignerFeature.State(
                    designPlan: designPlan,
                    roomGeometry: roomGeometry,
                    roomTitle: Self.buildRoomTitle(geometry: roomGeometry)
                )
            ) { ARDesignerFeature() }
        ))
    }

    public var body: some View {
        ARDesignerView(store: host.store, onClose: onClose)
            .navigationBarBackButtonHidden(true)
    }

    private static func buildRoomTitle(geometry: RoomGeometry) -> String {
        let area = Int(geometry.area)
        return "Комната · \(area) м²"
    }
}

// MARK: - Empty state (нет плана)

public struct ARDesignerEmptyState: View {
    let onScanTapped: () -> Void

    public init(onScanTapped: @escaping () -> Void = {}) {
        self.onScanTapped = onScanTapped
    }

    @Environment(\.aiColors) private var c

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(c.onSurfaceMuted)
            Text("Сначала отсканируйте комнату")
                .aiType(.title2)
                .foregroundStyle(c.onSurface)
            Text("Отсканируйте комнату, выберите стиль — и AI подберёт мебель для AR-примерки.")
                .aiType(.body)
                .foregroundStyle(c.onSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            PrimaryButton("Начать сканирование") {
                Haptics.medium()
                onScanTapped()
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.bg)
    }
}

// MARK: - Main view

struct ARDesignerView: View {
    @Bindable var store: StoreOf<ARDesignerFeature>
    let onClose: () -> Void

    /// Мост между TCA Store и RealityKit-сценой. Владеет ARSceneBuilder,
    /// snapshot-версионированием и task-отменой для incremental apply.
    @State private var sceneBridge = ARSceneBridge()
    @State private var draggedEntityID: UUID?
    /// Живая позиция во время переноса — для коммита в onEnded.
    @State private var dragLivePosition: SIMD3<Float>?
    /// Якорь камеры: его transform = положение устройства. Нужен, чтобы
    /// переводить жест с экрана в метры по полу с учётом расстояния
    /// до предмета и направления взгляда (как в IKEA Place).
    @State private var cameraAnchor = AnchorEntity(.camera)
    /// Размер вью в поинтах — для пересчёта «поинты → метры».
    @State private var viewSize: CGSize = .zero
    /// Вращение выбранного предмета на старте жеста (градусы).
    @State private var rotationStartDegrees: Float?
    /// Живое вращение во время жеста — для коммита в onEnded.
    @State private var rotationLiveDegrees: Float?

    /// Состояние ARKit-якоря пола. Управляет coaching overlay'ем
    /// "наведите камеру на пол" пока anchor не зарезолвлен.
    @State private var anchorState: AnchorState = .searching

    /// RealityKit SpatialTrackingSession для plane detection. Без явного
    /// run() RealityView не запускает tracking сам, и AnchorEntity(.plane)
    /// никогда не резолвится → grounding shadow не падает.
    @State private var trackingSession: SpatialTrackingSession?

    enum AnchorState: Equatable {
        case searching          // ещё ищем пол
        case anchored           // anchor нашёлся
        case unavailable(String) // tracking недоступен (нет permission/симулятор)
    }

    init(store: StoreOf<ARDesignerFeature>, onClose: @escaping () -> Void = {}) {
        self.store = store
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            arContent
                .ignoresSafeArea()
                .accessibilityHidden(true)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, item in
                    Color.clear
                        .frame(width: 80, height: 60)
                        .position(arAccessibilityPoint(idx: idx, count: store.items.count, w: w, h: h))
                        .accessibilityElement()
                        .accessibilityLabel(arAccessibilityLabel(item: item))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .ignoresSafeArea()

            VStack {
                ARTopBar(
                    title: store.roomTitle,
                    onClose: {
                        Haptics.light()
                        store.send(.closeTapped)
                        onClose()
                    },
                    onSwap: {
                        Haptics.selection()
                        store.send(.swapProviderTapped)
                    }
                )
                Spacer()
            }

            // Единый нижний стек: статусные плашки → FAB → бюджет → шторка.
            // Раньше каждый блок был отдельным оверлеем с «угаданным» отступом
            // (sheetHeight + N) — при несовпадении реальной высоты шторки
            // элементы наезжали друг на друга.
            VStack(spacing: 12) {
                Spacer()

                // Coaching: показываем пока anchor не найден на реальном
                // устройстве. На симуляторе AR-tracking недоступен — плашку
                // не показываем (там декоративный gradient вместо камеры).
                #if !targetEnvironment(simulator)
                coachingStatus
                #endif

                if let error = store.refineError {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                }

                HStack {
                    Spacer()
                    Button {
                        store.send(.fabTapped)
                    } label: {
                        ZStack {
                            Circle().fill(Color(hex: 0xD17F62))
                                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)

                VStack(spacing: 0) {
                    ARBudgetBar(
                        total: store.totalPrice,
                        max: store.budgetMax,
                        ratio: store.budgetRatio
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    ARFurnitureSheet(
                        items: store.items,
                        prices: store.prices,
                        selectedID: store.selectedItemID,
                        mode: store.sheetMode,
                        total: store.totalPrice,
                        isRefining: store.isRefining,
                        onToggle: {
                            Haptics.selection()
                            store.send(.sheetToggled)
                        },
                        onSelect: { id in
                            Haptics.light()
                            store.send(.itemTapped(id))
                            sceneBridge.liveSelection(store.selectedItemID == id ? nil : id)
                        },
                        onRemove: { id in
                            Haptics.warning()
                            sceneBridge.liveRemove(id: id)
                            store.send(.removeItem(id))
                        },
                        onRefine: {
                            Haptics.medium()
                            store.send(.refineTapped)
                        },
                        onCheckout: {
                            Haptics.medium()
                            store.send(.addToCartTapped)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: approvalBinding) {
            ARApprovalSheet(
                items: store.items,
                prices: store.prices,
                total: store.totalPrice,
                onCancel: {
                    Haptics.light()
                    store.send(.approvalCancelTapped)
                },
                onConfirm: {
                    Haptics.success()
                    store.send(.approvalConfirmTapped)
                }
            )
            .presentationDetents([.large])
            .presentationBackground(.regularMaterial)
        }
        .preferredColorScheme(.dark)
        .task { initialSubmit() }
        .onChange(of: store.items) { _, _ in submitSnapshot() }
        .onChange(of: store.selectedItemID) { _, _ in submitSnapshot() }
        .onChange(of: store.collisionReport) { _, _ in submitSnapshot() }
        .onDisappear { sceneBridge.dispose() }
    }

    // MARK: - AR Content

    @ViewBuilder
    private var arContent: some View {
        #if targetEnvironment(simulator)
        simulatorFallback
        #else
        realityContent
        #endif
    }

    private var realityContent: some View {
        RealityView { content in
            // Камера AR-passthrough: без этого RealityView на iOS рендерит
            // виртуальную камеру с чёрным фоном — пользователь видел
            // «чёрный экран» вместо своей комнаты.
            content.camera = .spatialTracking

            // Якорь камеры — для пересчёта жестов в метры по полу.
            content.add(cameraAnchor)

            if let root = sceneBridge.rootEntity {
                content.add(root)
            }
            // Подписка на состояние якоря пола — для coaching UX.
            _ = content.subscribe(to: AnchorStateEvents.DidAnchor.self) { _ in
                Task { @MainActor in anchorState = .anchored }
            }
            _ = content.subscribe(to: AnchorStateEvents.DidFailToAnchor.self) { event in
                let msg = "Не удалось закрепиться на полу: \(event.entity.name)"
                Task { @MainActor in anchorState = .unavailable(msg) }
            }
        } update: { content in
            // Если root entity появился после первого build — добавляем
            // его в content. RealityKit идемпотентно игнорирует повторное
            // добавление того же entity.
            if let root = sceneBridge.rootEntity, root.parent == nil {
                content.add(root)
            }
        }
        .gesture(tapGesture)
        .gesture(dragGesture)
        .simultaneousGesture(rotationGesture)
        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
        .task { await startTrackingSession() }
    }

    /// Запуск SpatialTrackingSession. iOS 26 не стартует tracking
    /// автоматически — без этого AnchorEntity(.plane) бесконечно "searching".
    /// Требует NSWorldSensingUsageDescription в Info.plist (уже есть в pbxproj).
    private func startTrackingSession() async {
        guard trackingSession == nil else { return }
        let session = SpatialTrackingSession()
        let config = SpatialTrackingSession.Configuration(
            tracking: [.plane]
        )
        let unavailable = await session.run(config)
        trackingSession = session
        if let unavailable, !unavailable.anchor.isEmpty {
            anchorState = .unavailable("AR-tracking недоступен на этом устройстве")
        }
    }

    // MARK: - Coaching status (поиск пола)

    @ViewBuilder
    private var coachingStatus: some View {
        switch anchorState {
        case .anchored:
            EmptyView()
        case .searching:
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .medium))
                Text("Наведите камеру на пол")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Наведите камеру на пол для размещения мебели")
        case .unavailable(let message):
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
        }
    }

    private var simulatorFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6D6354), Color(hex: 0x4A4339), Color(hex: 0x2C2820)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 12) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.4))
                Text("AR-сцена · \(store.items.count) предметов")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text("На устройстве здесь будет RealityView")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Жесты

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                guard let id = entityUUID(value.entity) else { return }
                Haptics.light()
                store.send(.itemTapped(id))
                sceneBridge.liveSelection(store.selectedItemID == id ? nil : id)
            }
    }

    /// Приблизительный вертикальный угол обзора AR-камеры iPhone (~60°).
    private static let cameraVerticalFOV: Float = 60 * .pi / 180

    /// Перенос в плоскости пола, откалиброванный по камере (подход IKEA
    /// Place): жест с экрана переводится в метры через реальное расстояние
    /// от устройства до предмета и FOV камеры, направления — вдоль взгляда,
    /// высота (y) фиксирована. Раньше был жёсткий маппинг «200pt ≈ 1 м» без
    /// учёта направления камеры — предметы уезжали мимо пальца («косо-криво»).
    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = entityUUID(value.entity),
                      let item = store.items[id: id],
                      let root = sceneBridge.rootEntity else { return }
                if draggedEntityID == nil { draggedEntityID = id }

                // Камера в пространстве root-якоря.
                let camTransform = cameraAnchor.transformMatrix(relativeTo: root)
                let camPosition = SIMD3<Float>(
                    camTransform.columns.3.x,
                    camTransform.columns.3.y,
                    camTransform.columns.3.z
                )

                // Оси жеста на полу: «вправо» и «от себя» вдоль взгляда камеры.
                let rawRight = SIMD3<Float>(
                    camTransform.columns.0.x, 0, camTransform.columns.0.z
                )
                let rawForward = SIMD3<Float>(
                    -camTransform.columns.2.x, 0, -camTransform.columns.2.z
                )
                guard simd_length(rawRight) > 0.001, simd_length(rawForward) > 0.001,
                      viewSize.height > 0 else { return }
                let right = simd_normalize(rawRight)
                let forward = simd_normalize(rawForward)

                // Поинты → метры: чем дальше предмет, тем больше метров в поинте.
                let distance = max(simd_length(camPosition - item.position), 0.3)
                let metersPerPoint = 2 * distance
                    * tan(Self.cameraVerticalFOV / 2)
                    / Float(viewSize.height)

                let dx = Float(value.gestureValue.translation.width) * metersPerPoint
                let dz = Float(value.gestureValue.translation.height) * metersPerPoint

                // Палец вверх по экрану = предмет дальше от камеры.
                let target = item.position + right * dx - forward * dz
                let newPosition = SIMD3<Float>(target.x, item.position.y, target.z)
                dragLivePosition = newPosition

                sceneBridge.liveTransform(
                    id: id,
                    position: newPosition,
                    rotation: rotationLiveDegrees ?? item.rotation
                )
            }
            .onEnded { _ in
                defer {
                    draggedEntityID = nil
                    dragLivePosition = nil
                }
                guard let id = draggedEntityID,
                      let finalPosition = dragLivePosition else { return }
                Haptics.selection()
                store.send(.itemMoved(id: id, newPosition: finalPosition))
            }
    }

    /// Вращение двумя пальцами — для выбранного предмета (тап → выделение,
    /// затем вращайте в любом месте экрана; не требует попадания двумя
    /// пальцами в предмет). Коммит — в `.itemRotated` (там же collision-check).
    private var rotationGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard let id = store.selectedItemID,
                      let item = store.items[id: id] else { return }
                if rotationStartDegrees == nil {
                    rotationStartDegrees = item.rotation
                }
                let newRotation = (rotationStartDegrees ?? 0) + Float(value.rotation.degrees)
                rotationLiveDegrees = newRotation

                sceneBridge.liveTransform(
                    id: id,
                    position: dragLivePosition ?? item.position,
                    rotation: newRotation
                )
            }
            .onEnded { _ in
                defer {
                    rotationStartDegrees = nil
                    rotationLiveDegrees = nil
                }
                guard let id = store.selectedItemID,
                      let finalRotation = rotationLiveDegrees else { return }
                Haptics.selection()
                store.send(.itemRotated(id: id, newRotation: finalRotation))
            }
    }

    // MARK: - Scene management (через ARSceneBridge)

    private func initialSubmit() {
        submitSnapshot()
    }

    private func submitSnapshot() {
        sceneBridge.submit(
            items: Array(store.items),
            geometry: store.roomGeometry,
            selectedID: store.selectedItemID,
            collisions: store.collisionReport
        )
    }

    // MARK: - Helpers

    private func entityUUID(_ entity: Entity) -> UUID? {
        var current: Entity? = entity
        while let e = current {
            if let uuid = UUID(uuidString: e.name) { return uuid }
            if e.name.hasPrefix("furniture_"),
               let uuid = UUID(uuidString: String(e.name.dropFirst("furniture_".count))) {
                return uuid
            }
            current = e.parent
        }
        return nil
    }

    private func arAccessibilityPoint(idx: Int, count: Int, w: CGFloat, h: CGFloat) -> CGPoint {
        let cols = max(Int(sqrt(Double(count))), 2)
        let row = idx / cols
        let col = idx % cols
        let x = w * (CGFloat(col) + 0.5) / CGFloat(cols)
        let y = h * 0.5 + CGFloat(row) * 70
        return CGPoint(x: x, y: y)
    }

    private func arAccessibilityLabel(item: FurnitureItem) -> String {
        let title = furnitureDisplayTitle(item)
        let dims = furnitureSubtitle(item)
        return "\(title), \(dims)"
    }

    private var approvalBinding: Binding<Bool> {
        Binding(
            get: { store.isApprovalPresented },
            set: { newValue in
                if !newValue { store.send(.approvalCancelTapped) }
            }
        )
    }
}
