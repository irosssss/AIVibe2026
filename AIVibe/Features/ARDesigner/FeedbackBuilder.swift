// AIVibe/Features/ARDesigner/FeedbackBuilder.swift
// Построение UserFeedback из сравнения оригинального плана и текущих позиций.

import Foundation
import simd

public enum FeedbackBuilder: Sendable {

    private static let moveThreshold: Float = 0.1

    public static func buildFeedback(
        originalPlan: RoomDesignPlan,
        currentItems: [FurnitureItem],
        userComment: String? = nil
    ) -> UserFeedback {
        let originalByID = Dictionary(
            uniqueKeysWithValues: originalPlan.items.map { ($0.id, $0) }
        )

        var dislikes: [String] = []
        var keepItems: [String] = []

        for current in currentItems {
            guard let original = originalByID[current.id] else { continue }
            let delta = simd_length(current.position - original.position)
            let rotationDelta = abs(current.rotation - original.rotation)

            if delta > moveThreshold || rotationDelta > 15 {
                dislikes.append(current.itemType)
            } else {
                keepItems.append(current.itemType)
            }
        }

        let removed = originalPlan.items.filter { orig in
            !currentItems.contains { $0.id == orig.id }
        }
        for item in removed {
            dislikes.append("\(item.itemType) (удалён)")
        }

        return UserFeedback(
            dislikes: dislikes,
            keepItems: keepItems,
            freeText: userComment
        )
    }
}
