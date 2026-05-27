// AIVibe/Features/ARDesigner/CollisionDetector.swift
// Типы FurnitureItem и DesignPlan; проверка коллизий в расстановке мебели.

import Foundation
import simd

// MARK: - Предмет мебели

public struct FurnitureItem: Codable, Sendable, Equatable {
    public let id: UUID
    public let itemType: String
    public let brand: String
    public let article: String
    public let position: SIMD3<Float>
    public let rotation: Float       // градусы вокруг оси Y
    public let size: SIMD3<Float>    // ширина, высота, глубина в метрах
    public let usdzURL: String

    public init(
        id: UUID = UUID(),
        itemType: String,
        brand: String,
        article: String,
        position: SIMD3<Float>,
        rotation: Float,
        size: SIMD3<Float>,
        usdzURL: String
    ) {
        self.id = id
        self.itemType = itemType
        self.brand = brand
        self.article = article
        self.position = position
        self.rotation = rotation
        self.size = size
        self.usdzURL = usdzURL
    }
}

// MARK: - План расстановки мебели

public struct RoomDesignPlan: Codable, Sendable, Equatable {
    public let id: UUID
    public let items: [FurnitureItem]
    public let explanation: String
    public let confidence: Double
    public let generatedAt: Date
    public let providerName: String

    public init(
        id: UUID = UUID(),
        items: [FurnitureItem],
        explanation: String,
        confidence: Double,
        generatedAt: Date = Date(),
        providerName: String
    ) {
        self.id = id
        self.items = items
        self.explanation = explanation
        self.confidence = confidence
        self.generatedAt = generatedAt
        self.providerName = providerName
    }
}

// MARK: - Отчёт о коллизиях

public struct CollisionReport: Sendable {
    public let hasCollisions: Bool
    public let collidingPairs: [(FurnitureItem, FurnitureItem)]
    public let itemsOutOfBounds: [FurnitureItem]
    public let blockedDoors: [DoorGeometry]

    public var isClean: Bool { !hasCollisions && itemsOutOfBounds.isEmpty && blockedDoors.isEmpty }
}

// MARK: - Протокол

public protocol CollisionDetecting: Sendable {
    func check(plan: RoomDesignPlan, room: RoomGeometry) -> CollisionReport
}

// MARK: - Реализация

public struct CollisionDetector: CollisionDetecting {

    public init() {}

    public func check(plan: RoomDesignPlan, room: RoomGeometry) -> CollisionReport {
        let items = plan.items
        var collidingPairs: [(FurnitureItem, FurnitureItem)] = []
        var outOfBounds: [FurnitureItem] = []
        var blockedDoors: [DoorGeometry] = []

        // AABB коллизии между каждой парой предметов
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                if aabbOverlap(items[i], items[j]) {
                    collidingPairs.append((items[i], items[j]))
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

        // Проверка свободной зоны 80 см перед дверями
        let doorClearance: Float = 0.80
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
        // Упрощённый AABB без поворота (достаточно для первичной проверки)
        let minGap: Float = 0.05  // 5 см минимальный зазор
        let dx = abs(a.position.x - b.position.x)
        let dz = abs(a.position.z - b.position.z)
        let sumHW = (a.size.x + b.size.x) / 2 + minGap
        let sumHD = (a.size.z + b.size.z) / 2 + minGap
        return dx < sumHW && dz < sumHD
    }
}
