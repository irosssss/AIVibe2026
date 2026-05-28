// AIVibe/Features/ARDesigner/Domain/CollisionTypes.swift
// Domain-типы для отчёта о коллизиях. Pure value types.
// Используется CollisionService (L4) и ARDesignerFeature (L5).

import Foundation

// MARK: - Пара столкнувшихся предметов

public struct CollidingPair: Sendable, Equatable {
    public let first: FurnitureItem
    public let second: FurnitureItem

    public init(_ a: FurnitureItem, _ b: FurnitureItem) {
        self.first = a
        self.second = b
    }
}

// MARK: - Отчёт о коллизиях

public struct CollisionReport: Sendable, Equatable {
    public let hasCollisions: Bool
    public let collidingPairs: [CollidingPair]
    public let itemsOutOfBounds: [FurnitureItem]
    public let blockedDoors: [DoorGeometry]

    public init(
        hasCollisions: Bool,
        collidingPairs: [CollidingPair],
        itemsOutOfBounds: [FurnitureItem],
        blockedDoors: [DoorGeometry]
    ) {
        self.hasCollisions = hasCollisions
        self.collidingPairs = collidingPairs
        self.itemsOutOfBounds = itemsOutOfBounds
        self.blockedDoors = blockedDoors
    }

    public var isClean: Bool {
        !hasCollisions && itemsOutOfBounds.isEmpty && blockedDoors.isEmpty
    }
}
