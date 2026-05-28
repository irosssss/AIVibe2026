// AIVibe/Features/ARDesigner/Domain/FurnitureItem.swift
// Domain-тип: предмет мебели в плане расстановки.
// Pure value type, не зависит от RealityKit/UIKit/TCA.

import Foundation
import simd

public struct FurnitureItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let itemType: String
    public let brand: String
    public let article: String
    public var position: SIMD3<Float>
    public var rotation: Float       // градусы вокруг оси Y
    public var size: SIMD3<Float>    // ширина, высота, глубина в метрах
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
