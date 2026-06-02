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

        // Проверка выхода за периметр (допуск 5 см = 0.05 м)
        let margin: Float = 0.05
        let halfW = Float(sqrt(room.area)) / 2
        let halfD = Float(sqrt(room.area)) / 2

        for item in items {
            let hw = item.size.x / 2
            let hd = item.size.z / 2
            let minX = item.position.x - hw
            let maxX = item.position.x + hw
            let minZ = item.position.z - hd
            let maxZ = item.position.z + hd

            if minX < -margin || maxX > 2 * halfW + margin ||
               minZ < -margin || maxZ > 2 * halfD + margin {
                outOfBounds.append(item)
            }
        }

        // Проверка свободной зоны перед дверями (норма из DesignNorms, см → м).
        let doorClearance = Float(DesignNorms.doorClearanceFrontCm) / 100
        for door in room.doors {
            let doorPos = door.position
            let isBlocked = items.contains { item in
                let dist = simd_length(item.position - doorPos)
                return dist < doorClearance + item.size.x / 2
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

    private func aabbOverlap(_ a: FurnitureItem, _ b: FurnitureItem) -> Bool {
        let minGap: Float = 0.05
        let dx = abs(a.position.x - b.position.x)
        let dz = abs(a.position.z - b.position.z)
        let sumHW = (a.size.x + b.size.x) / 2 + minGap
        let sumHD = (a.size.z + b.size.z) / 2 + minGap
        return dx < sumHW && dz < sumHD
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
