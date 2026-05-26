// AIVibe/Features/ARDesigner/ImageGenClient.swift
// Дополняет SESSION_03 — не конфликтует с RoomScanManager и RealityDesignerView

import ComposableArchitecture
import Foundation

struct GeneratedImage: Codable, Equatable, Identifiable {
    let id: UUID
    let url: URL
    let prompt: String
    // Тип комнаты из SESSION_05 — переиспользуем, не дублируем
    let roomType: RoomType
    let style: DesignStyle
}

struct ImageGenClient {
    var generate: @Sendable (
        _ style: DesignStyle,
        _ roomType: RoomType,
        _ colorPalette: [ColorSuggestion]
    ) async throws -> [GeneratedImage]
}

// MARK: - Nested types for ImageGen response

private struct ImageGenResponse: Codable {
    struct Item: Codable { let url: String; let prompt: String }
    let images: [Item]
}

extension ImageGenClient: DependencyKey {
    static let liveValue = ImageGenClient(
        generate: { style, roomType, palette in
            guard let url = URL(string: "https://functions.yandexcloud.net/YOUR_IMAGEGEN_FUNCTION_ID") else {
                throw URLError(.badURL)
            }

            let body: [String: Any] = [
                "style": style.rawValue,
                "roomType": roomType.rawValue,
                "colorPalette": palette.map { $0.hex }.joined(separator: ", "),
                "userId": "current_user_id"
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 150

            let (data, _) = try await URLSession.shared.data(for: request)

            let decoded = try JSONDecoder().decode(ImageGenResponse.self, from: data)
            return decoded.images.compactMap { item in
                guard let imageURL = URL(string: item.url) else { return nil }
                return GeneratedImage(
                    id: UUID(),
                    url: imageURL,
                    prompt: item.prompt,
                    roomType: roomType,
                    style: style
                )
            }
        }
    )

    static let testValue = ImageGenClient(
        generate: { style, roomType, _ in
            guard let placeholderURL = URL(string: "https://placeholder.com") else { return [] }
            return [GeneratedImage(
                id: UUID(),
                url: placeholderURL,
                prompt: "test prompt",
                roomType: roomType,
                style: style
            )]
        }
    )
}

extension DependencyValues {
    var imageGenClient: ImageGenClient {
        get { self[ImageGenClient.self] }
        set { self[ImageGenClient.self] = newValue }
    }
}
