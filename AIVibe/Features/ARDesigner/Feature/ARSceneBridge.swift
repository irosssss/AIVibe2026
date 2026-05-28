// AIVibe/Features/ARDesigner/Feature/ARSceneBridge.swift
// L5: @MainActor @Observable мост между TCA Store (Sendable) и
// @MainActor ARSceneBuilder. Владеет:
//   - ARSceneBuilder (entity-граф)
//   - version-счётчиком ARSceneSnapshot
//   - lastSnapshot для diff-вычисления
//   - applyTask для отмены устаревших применений (race "drag-end vs refine")
//
// View вызывает `attach(store:)` один раз — bridge сам подписывается на
// store и шлёт snapshot'ы в builder через apply(snapshot:previous:).

import Foundation
import RealityKit
import Observation

@MainActor
@Observable
public final class ARSceneBridge {

    public let builder: ARSceneBuilder

    /// Корень для RealityView.content.add — ставится после первого buildScene.
    public private(set) var rootEntity: Entity?

    private var version: Int = 0
    private var lastSnapshot: ARSceneSnapshot?
    private var applyTask: Task<Void, Never>?

    public init() {
        let loader = USDZLoader()
        let factory = FurnitureEntityFactory(loader: loader)
        self.builder = ARSceneBuilder(entityManager: factory)
    }

    // MARK: - Public API

    /// Применяет новый snapshot к сцене. Версия монотонна — старые
    /// snapshot'ы автоматически отбрасываются builder.apply'ем.
    /// Параллельный применяющий Task отменяется перед запуском нового.
    public func submit(items: [FurnitureItem],
                       geometry: RoomGeometry,
                       selectedID: UUID?,
                       collisions: CollisionReport?) {
        version += 1
        let snapshot = ARSceneSnapshot(
            version: version,
            items: items,
            geometry: geometry,
            selectedID: selectedID,
            collisions: collisions
        )

        let previous = lastSnapshot
        lastSnapshot = snapshot

        applyTask?.cancel()
        applyTask = Task { [weak self] in
            guard let self else { return }
            await self.builder.apply(snapshot: snapshot, previous: previous)
            if Task.isCancelled { return }
            self.rootEntity = await self.currentRoot()
        }
    }

    /// Direct hot-path для одиночных interactive-обновлений во время drag.
    /// НЕ повышает версию — это in-flight transform feedback, snapshot
    /// прилетит позже из reducer при itemMoved.
    public func liveTransform(id: UUID,
                              position: SIMD3<Float>,
                              rotation: Float) {
        builder.updateItemTransform(entityID: id, position: position, rotation: rotation)
    }

    /// Direct hot-path для toggle selection без полного snapshot'а.
    public func liveSelection(_ id: UUID?) {
        builder.updateSelection(itemID: id)
    }

    /// Direct hot-path для удаления — снимок прилетит из reducer следом.
    public func liveRemove(id: UUID) {
        builder.removeItem(id: id)
    }

    public func dispose() {
        applyTask?.cancel()
        applyTask = nil
        lastSnapshot = nil
        builder.dispose()
        rootEntity = nil
        version = 0
    }

    // MARK: - Internal

    private func currentRoot() async -> Entity? {
        // builder создаёт root в первом buildScene; читаем через reflection
        // через публичный accessor — для этого добавим тонкий API.
        return builder.currentRoot()
    }
}
