// AIVibe/Features/ARDesigner/Services/CollisionService.swift
// L4 Service: проверка коллизий между предметами мебели,
// выход за периметр комнаты, блокировка дверей.
// Pure logic, Sendable. Не зависит от RealityKit/UIKit.

import Foundation
import simd
import ComposableArchitecture

// MARK: - Протокол

public protocol CollisionDetecting: Sendable {
    func check(plan: RoomDesignPlan, room: RoomGeometry) -> CollisionReport
}

// MARK: - Реализация

public struct CollisionDetector: CollisionDetecting {

    public init() {}

    public func check(plan: RoomDesignPlan, room: RoomGeometry) -> CollisionReport {
        let items = plan.items
        var collidingPairs: [CollidingPair] = []
        var outOfBounds: [FurnitureItem] = []
        var blockedDoors: [DoorGeometry] = []

        // AABB коллизии между каждой парой предметов
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                if aabbOverlap(items[i], items[j]) {
                    collidingPairs.append(CollidingPair(items[i], items[j]))
                }
            }
        }

        // Проверка выхода за периметр (допуск 5 см = 0.05 м).
        // A2: границы — реальный bbox по стенам (RoomGeometry.floorBounds),
        // а не квадрат из площади: вытянутые комнаты больше не дают ложных срабатываний.
        let margin: Float = 0.05
        let bounds = room.floorBounds

        for item in items {
            let (hw, hd) = halfExtents(item)
            let minX = item.position.x - hw
            let maxX = item.position.x + hw
            let minZ = item.position.z - hd
            let maxZ = item.position.z + hd

            if minX < bounds.minX - margin || maxX > bounds.maxX + margin ||
               minZ < bounds.minZ - margin || maxZ > bounds.maxZ + margin {
                outOfBounds.append(item)
            }
        }

        // Проверка свободной зоны перед дверями (норма из DesignNorms, см → м).
        // Радиус — по большему полуразмеру следа (синхронизирован с ArrangementEngine).
        let doorClearance = Float(DesignNorms.doorClearanceFrontCm) / 100
        for door in room.doors {
            let doorPos = door.position
            let isBlocked = items.contains { item in
                let dist = simd_length(item.position - doorPos)
                return dist < doorClearance + max(item.size.x, item.size.z) / 2
            }
            if isBlocked {
                blockedDoors.append(door)
            }
        }

        return CollisionReport(
            hasCollisions: !collidingPairs.isEmpty,
            collidingPairs: collidingPairs,
            itemsOutOfBounds: outOfBounds,
            blockedDoors: blockedDoors
        )
    }

    // MARK: - AABB с учётом rotation

    /// Полуразмеры следа на полу с учётом поворота вокруг Y: при повороте,
    /// близком к 90°/270°, ширина и глубина меняются местами.
    /// A2: раньше поворот игнорировался — повёрнутый диван у боковой стены
    /// давал ложные коллизии/выход за границы.
    private func halfExtents(_ item: FurnitureItem) -> (hw: Float, hd: Float) {
        let normalized = abs(item.rotation.truncatingRemainder(dividingBy: 180))
        let isRotated = abs(normalized - 90) < 45
        return isRotated
            ? (item.size.z / 2, item.size.x / 2)
            : (item.size.x / 2, item.size.z / 2)
    }

    private func aabbOverlap(_ a: FurnitureItem, _ b: FurnitureItem) -> Bool {
        let minGap: Float = 0.05
        let (ahw, ahd) = halfExtents(a)
        let (bhw, bhd) = halfExtents(b)
        let dx = abs(a.position.x - b.position.x)
        let dz = abs(a.position.z - b.position.z)
        return dx < ahw + bhw + minGap && dz < ahd + bhd + minGap
    }
}

// MARK: - TCA DependencyKey

private enum CollisionDetectorKey: DependencyKey {
    static let liveValue: any CollisionDetecting = CollisionDetector()
    static let testValue: any CollisionDetecting = CollisionDetector()
}

extension DependencyValues {
    public var collisionDetector: any CollisionDetecting {
        get { self[CollisionDetectorKey.self] }
        set { self[CollisionDetectorKey.self] = newValue }
    }
}
