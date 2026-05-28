// AIVibe/Features/ARDesigner/ARDesignerView.swift
// RealityKit AR-сцена с жестами + glass-UI overlay.

import ComposableArchitecture
import RealityKit
import SwiftUI

// MARK: - Public entry

public struct ARDesignerScreen: View {
    private let designPlan: RoomDesignPlan
    private let roomGeometry: RoomGeometry
    private let onClose: () -> Void

    public init(
        designPlan: RoomDesignPlan,
        roomGeometry: RoomGeometry,
        onClose: @escaping () -> Void = {}
    ) {
        self.designPlan = designPlan
        self.roomGeometry = roomGeometry
        self.onClose = onClose
    }

    public var body: some View {
        let store = Store(
            initialState: ARDesignerFeature.State(
                designPlan: designPlan,
                roomGeometry: roomGeometry,
                roomTitle: buildRoomTitle(geometry: roomGeometry)
            )
        ) { ARDesignerFeature() }

        ARDesignerView(store: store, onClose: onClose)
            .navigationBarBackButtonHidden(true)
    }

    private func buildRoomTitle(geometry: RoomGeometry) -> String {
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

            // Coaching overlay: показываем пока anchor не найден на реальном
            // устройстве. На симуляторе AR-tracking недоступен — overlay не
            // показываем (там декоративный gradient вместо камеры).
            #if !targetEnvironment(simulator)
            coachingOverlay
            #endif

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

            VStack(spacing: 0) {
                Spacer()
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

            VStack {
                Spacer()
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
                .padding(.bottom, sheetHeight + 88)
            }

            if let error = store.refineError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.bottom, sheetHeight + 160)
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

    // MARK: - Coaching overlay (поиск пола)

    @ViewBuilder
    private var coachingOverlay: some View {
        switch anchorState {
        case .anchored:
            EmptyView()
        case .searching:
            VStack {
                Spacer()
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
                .padding(.bottom, sheetHeight + 100)
            }
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Наведите камеру на пол для размещения мебели")
        case .unavailable(let message):
            VStack {
                Spacer()
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.bottom, sheetHeight + 160)
            }
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

    // ~200pt экрана ≈ 1 метр в AR (приблизительно, зависит от расстояния)
    private static let pixelsPerMeter: CGFloat = 200

    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = entityUUID(value.entity) else { return }
                if draggedEntityID == nil { draggedEntityID = id }
                guard let item = store.items[id: id] else { return }

                let dx = Float(value.gestureValue.translation.width / Self.pixelsPerMeter)
                let dz = Float(value.gestureValue.translation.height / Self.pixelsPerMeter)

                let newPosition = SIMD3<Float>(
                    item.position.x + dx,
                    item.position.y,
                    item.position.z + dz
                )

                sceneBridge.liveTransform(
                    id: id,
                    position: newPosition,
                    rotation: item.rotation
                )
            }
            .onEnded { value in
                guard let id = draggedEntityID else { return }
                draggedEntityID = nil
                guard let item = store.items[id: id] else { return }

                let dx = Float(value.gestureValue.translation.width / Self.pixelsPerMeter)
                let dz = Float(value.gestureValue.translation.height / Self.pixelsPerMeter)

                let finalPosition = SIMD3<Float>(
                    item.position.x + dx,
                    item.position.y,
                    item.position.z + dz
                )

                Haptics.selection()
                store.send(.itemMoved(id: id, newPosition: finalPosition))
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

    private var sheetHeight: CGFloat {
        store.sheetMode == .expanded ? 540 : 280
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
