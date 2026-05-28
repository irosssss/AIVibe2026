// AIVibe/Features/ARDesigner/Domain/ARSceneSnapshot.swift
// Domain-snapshot того, что должно быть в AR-сцене сейчас. Pure Sendable
// value-тип. Несёт `version` для устранения race "stale apply" —
// ARSceneBridge применяет только snapshot'ы с возрастающей версией.

import Foundation

public struct ARSceneSnapshot: Sendable, Equatable {
    public let version: Int
    public let items: [FurnitureItem]
    public let geometry: RoomGeometry
    public let selectedID: UUID?
    public let collisions: CollisionReport?

    public init(
        version: Int,
        items: [FurnitureItem],
        geometry: RoomGeometry,
        selectedID: UUID? = nil,
        collisions: CollisionReport? = nil
    ) {
        self.version = version
        self.items = items
        self.geometry = geometry
        self.selectedID = selectedID
        self.collisions = collisions
    }
}
