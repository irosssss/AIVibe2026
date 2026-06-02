// AIVibe/Features/ARDesigner/Domain/RoomDesignPlan.swift
// Domain-тип: результат работы DesignerAgent — план мебели для комнаты.
// Pure value type, не зависит от RealityKit/UIKit/TCA.

import Foundation

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
