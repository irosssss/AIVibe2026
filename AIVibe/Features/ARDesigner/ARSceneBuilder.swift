// AIVibe/Features/ARDesigner/ARSceneBuilder.swift
// Преобразование RoomDesignPlan + RoomGeometry в иерархию RealityKit Entity.

import Foundation
import RealityKit
import simd
import Logging

// MARK: - Результат построения сцены

public struct ARSceneResult: @unchecked Sendable {
    public let rootEntity: Entity
    public let furnitureEntities: [UUID: Entity]
    public let floorEntity: Entity
}

// MARK: - Построитель AR-сцены

@MainActor
public final class ARSceneBuilder {

    private let entityManager: FurnitureEntityFactory
    private let collisionDetector: any CollisionDetecting
    private let logger = Logger(label: "ar.scene-builder")

    private var rootEntity: Entity?
    private var furnitureGroup: Entity?
    private var furnitureEntities: [UUID: Entity] = [:]
    private var collisionOverlays: [UUID: Entity] = [:]
    private var selectionOverlay: Entity?
    private var selectedID: UUID?

    public init(
        entityManager: FurnitureEntityFactory,
        collisionDetector: any CollisionDetecting = CollisionDetector()
    ) {
        self.entityManager = entityManager
        self.collisionDetector = collisionDetector
    }

    /// Текущий корневой Entity сцены (после первого buildScene/apply).
    /// Используется ARSceneBridge для содержимого RealityView.
    public func currentRoot() -> Entity? {
        rootEntity
    }

    // MARK: - Построение сцены

    public func buildScene(
        plan: RoomDesignPlan,
        geometry: RoomGeometry
    ) async -> ARSceneResult {
        // Якорим корень сцены на горизонтальную плоскость пола, чтобы
        // GroundingShadowComponent имел реальную поверхность для теней,
        // и чтобы вся мебель привязалась к найденному ARKit-плану.
        // minimumBounds — нижняя граница "разумного пола" 0.5×0.5м.
        let root = AnchorEntity(
            .plane(
                .horizontal,
                classification: .floor,
                minimumBounds: SIMD2<Float>(0.5, 0.5)
            )
        )
        root.name = "ar-scene-root"

        let floor = buildFloorPlane(geometry: geometry)
        root.addChild(floor)

        let wallGroup = buildWallGroup(geometry: geometry)
        root.addChild(wallGroup)

        let fGroup = Entity()
        fGroup.name = "furniture-group"
        root.addChild(fGroup)

        furnitureEntities.removeAll()
        await entityManager.preloadAll(items: plan.items)

        for item in plan.items {
            let entity = await entityManager.loadEntity(for: item)
            entity.name = "furniture_\(item.id.uuidString)"
            fGroup.addChild(entity)
            furnitureEntities[item.id] = entity
        }

        self.rootEntity = root
        self.furnitureGroup = fGroup

        let report = collisionDetector.check(plan: plan, room: geometry)
        highlightCollisions(report: report)

        logger.info("Сцена построена: \(plan.items.count) предметов")

        return ARSceneResult(
            rootEntity: root,
            furnitureEntities: furnitureEntities,
            floorEntity: floor
        )
    }

    // MARK: - Обновление трансформов

    public func updateItemTransform(
        entityID: UUID,
        position: SIMD3<Float>,
        rotation: Float
    ) {
        guard let entity = furnitureEntities[entityID] else { return }
        entity.position = position
        let radians = rotation * .pi / 180
        entity.orientation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - Выделение

    public func updateSelection(itemID: UUID?) {
        if let prev = selectedID, let overlay = selectionOverlay {
            furnitureEntities[prev]?.removeChild(overlay)
        }
        selectionOverlay = nil
        selectedID = itemID

        guard let id = itemID, let entity = furnitureEntities[id] else { return }
        let bounds = entity.visualBounds(relativeTo: entity)
        let size = bounds.extents * 1.04
        let mesh = MeshResource.generateBox(size: size)
        var material = UnlitMaterial(color: .white.withAlphaComponent(0.3))
        material.faceCulling = .front
        let overlay = ModelEntity(mesh: mesh, materials: [material])
        overlay.name = "selection-overlay"
        overlay.position = bounds.center
        entity.addChild(overlay)
        selectionOverlay = overlay
        selectedID = id
    }

    // MARK: - Коллизии

    public func highlightCollisions(report: CollisionReport) {
        for (id, overlay) in collisionOverlays {
            furnitureEntities[id]?.removeChild(overlay)
        }
        collisionOverlays.removeAll()

        let collidingIDs = Set(
            report.collidingPairs.flatMap { [$0.first.id, $0.second.id] }
            + report.itemsOutOfBounds.map(\.id)
        )

        for id in collidingIDs {
            guard let entity = furnitureEntities[id] else { continue }
            let bounds = entity.visualBounds(relativeTo: entity)
            let size = bounds.extents * 1.03
            let mesh = MeshResource.generateBox(size: size)
            let material = UnlitMaterial(color: .red.withAlphaComponent(0.25))
            let overlay = ModelEntity(mesh: mesh, materials: [material])
            overlay.name = "collision-overlay"
            overlay.position = bounds.center
            entity.addChild(overlay)
            collisionOverlays[id] = overlay
        }
    }

    // MARK: - Добавление / удаление

    public func addItem(_ item: FurnitureItem) async -> Entity? {
        guard let fGroup = furnitureGroup else { return nil }
        let entity = await entityManager.loadEntity(for: item)
        entity.name = "furniture_\(item.id.uuidString)"
        fGroup.addChild(entity)
        furnitureEntities[item.id] = entity
        return entity
    }

    public func removeItem(id: UUID) {
        guard let entity = furnitureEntities.removeValue(forKey: id) else { return }
        if let overlay = collisionOverlays.removeValue(forKey: id) {
            entity.removeChild(overlay)
        }
        entity.removeFromParent()
        if selectedID == id {
            selectionOverlay = nil
            selectedID = nil
        }
    }

    // MARK: - Snapshot apply (incremental diff)

    private var lastSnapshotVersion: Int = -1

    /// Применяет минимальный diff между предыдущим snapshot'ом и новым.
    /// Версия монотонна — устаревшие snapshot'ы игнорируются.
    ///
    /// - Если сцена ещё не построена (нет rootEntity) — strong-build через
    ///   `buildScene`. Это initial call.
    /// - Иначе — diff через `SceneDiffer` + минимальные мутации.
    @discardableResult
    public func apply(snapshot: ARSceneSnapshot, previous: ARSceneSnapshot?) async -> Bool {
        // Версия монотонна — старые snapshot'ы отбрасываем.
        guard snapshot.version > lastSnapshotVersion else { return false }
        lastSnapshotVersion = snapshot.version

        // Initial build: сцены ещё нет.
        guard rootEntity != nil else {
            _ = await buildScene(
                plan: RoomDesignPlan(
                    items: snapshot.items,
                    explanation: "",
                    confidence: 0,
                    providerName: ""
                ),
                geometry: snapshot.geometry
            )
            if let id = snapshot.selectedID { updateSelection(itemID: id) }
            if let report = snapshot.collisions { highlightCollisions(report: report) }
            return true
        }

        // Incremental diff: применяем только delta-операции.
        let delta = SceneDiffer.diff(old: previous, new: snapshot)
        guard !delta.isEmpty else { return true }

        for op in delta.operations {
            switch op {
            case .add(let item):
                _ = await addItem(item)
            case .remove(let id):
                removeItem(id: id)
            case .updateTransform(let id, let position, let rotation):
                updateItemTransform(entityID: id, position: position, rotation: rotation)
            case .reselect(let id):
                updateSelection(itemID: id)
            case .updateCollisions(let report):
                if let report {
                    highlightCollisions(report: report)
                } else {
                    // Snapshot без коллизий — чистим overlay'и.
                    highlightCollisions(report: CollisionReport(
                        hasCollisions: false,
                        collidingPairs: [],
                        itemsOutOfBounds: [],
                        blockedDoors: []
                    ))
                }
            }
        }
        return true
    }

    /// Очистка сцены — для dismiss/teardown. Освобождает entity-граф.
    public func dispose() {
        for entity in furnitureEntities.values {
            entity.removeFromParent()
        }
        furnitureEntities.removeAll()
        collisionOverlays.removeAll()
        selectionOverlay = nil
        selectedID = nil
        rootEntity?.removeFromParent()
        rootEntity = nil
        furnitureGroup = nil
        lastSnapshotVersion = -1
    }

    // MARK: - Построение пола

    private func buildFloorPlane(geometry: RoomGeometry) -> Entity {
        let side = Float(sqrt(geometry.area))
        let mesh = MeshResource.generatePlane(width: side, depth: side)
        let material = OcclusionMaterial()
        let floor = ModelEntity(mesh: mesh, materials: [material])
        floor.name = "floor-plane"
        floor.position = SIMD3<Float>(side / 2, 0, side / 2)
        return floor
    }

    // MARK: - Построение стен (debug)

    private func buildWallGroup(geometry: RoomGeometry) -> Entity {
        let group = Entity()
        group.name = "wall-group"
        group.isEnabled = false

        for (i, wall) in geometry.walls.enumerated() {
            let center = (wall.start + wall.end) * 0.5
            let length = Float(wall.length)
            let height = Float(wall.height)
            let mesh = MeshResource.generateBox(
                size: SIMD3<Float>(length, height, 0.02)
            )
            let material = UnlitMaterial(
                color: .systemBlue.withAlphaComponent(0.15)
            )
            let wallEntity = ModelEntity(mesh: mesh, materials: [material])
            wallEntity.name = "wall_\(i)"
            wallEntity.position = SIMD3<Float>(center.x, height / 2, center.z)

            let direction = simd_normalize(wall.end - wall.start)
            let angle = atan2(direction.x, direction.z)
            wallEntity.orientation = simd_quatf(
                angle: angle,
                axis: SIMD3<Float>(0, 1, 0)
            )

            group.addChild(wallEntity)
        }

        return group
    }
}
