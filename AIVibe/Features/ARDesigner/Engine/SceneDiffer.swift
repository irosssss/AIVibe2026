// AIVibe/Features/ARDesigner/Engine/SceneDiffer.swift
// L3 pure: вычисляет минимальный набор операций между двумя ARSceneSnapshot.
// Используется ARSceneGraph.apply() чтобы НЕ перестраивать всю сцену
// на каждое изменение items (фикс race "drag-end vs refine-complete"
// и потерянного AnchorEntity при rebuild).

import Foundation
import simd

public enum SceneOperation: Sendable, Equatable {
    /// Добавить новый item в сцену.
    case add(FurnitureItem)
    /// Удалить item из сцены по id.
    case remove(UUID)
    /// Обновить transform (position/rotation) существующего item.
    case updateTransform(id: UUID, position: SIMD3<Float>, rotation: Float)
    /// Изменить выделение — nil сбрасывает.
    case reselect(UUID?)
    /// Перерисовать collision overlays под новый отчёт.
    case updateCollisions(CollisionReport?)
}

public struct SceneDelta: Sendable, Equatable {
    public let operations: [SceneOperation]
    public let isEmpty: Bool

    public init(operations: [SceneOperation]) {
        self.operations = operations
        self.isEmpty = operations.isEmpty
    }
}

public enum SceneDiffer {

    /// Сравнивает старый и новый snapshot, возвращает минимальный delta.
    /// Если `old == nil` — добавляет все items как .add (initial build).
    /// Threshold transform-сравнения: 1мм/0.1° чтобы float-noise не давал
    /// лишних мутаций.
    public static func diff(
        old: ARSceneSnapshot?,
        new: ARSceneSnapshot
    ) -> SceneDelta {
        var ops: [SceneOperation] = []

        // Initial build: всё добавляем как новое.
        guard let old else {
            for item in new.items {
                ops.append(.add(item))
            }
            if let id = new.selectedID {
                ops.append(.reselect(id))
            }
            if new.collisions != nil {
                ops.append(.updateCollisions(new.collisions))
            }
            return SceneDelta(operations: ops)
        }

        let oldByID = Dictionary(uniqueKeysWithValues: old.items.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.items.map { ($0.id, $0) })

        // Удалённые
        for id in oldByID.keys where newByID[id] == nil {
            ops.append(.remove(id))
        }

        // Добавленные + изменённые transform
        for (id, newItem) in newByID {
            if let oldItem = oldByID[id] {
                if !transformsEqual(oldItem, newItem) {
                    ops.append(.updateTransform(
                        id: id,
                        position: newItem.position,
                        rotation: newItem.rotation
                    ))
                }
            } else {
                ops.append(.add(newItem))
            }
        }

        if old.selectedID != new.selectedID {
            ops.append(.reselect(new.selectedID))
        }

        if old.collisions != new.collisions {
            ops.append(.updateCollisions(new.collisions))
        }

        return SceneDelta(operations: ops)
    }

    private static func transformsEqual(_ a: FurnitureItem, _ b: FurnitureItem) -> Bool {
        let posDelta = simd_length(a.position - b.position)
        let rotDelta = abs(a.rotation - b.rotation)
        return posDelta < 0.001 && rotDelta < 0.1
    }
}
