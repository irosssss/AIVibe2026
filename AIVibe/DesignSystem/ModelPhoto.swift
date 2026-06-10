// AIVibe/DesignSystem/ModelPhoto.swift
// Миниатюра 3D-модели из бандла приложения: рендер через QuickLookThumbnailing.
// Пока рендерится (или файла нет) — показывается PhotoSlot, публичный API
// зеркалит его, чтобы замена в существующих экранах была построчной.

import SwiftUI
import UIKit
import QuickLookThumbnailing

/// Фото товара из его 3D-модели (USDZ в бандле).
/// `usdzFile == nil` или ошибка рендера → обычный PhotoSlot.
public struct ModelPhoto: View {
    public let usdzFile: String?
    public let tone: AIPhotoTone
    public let label: String?
    public let cornerRadius: CGFloat
    public let aspectRatio: CGFloat?

    @State private var thumbnail: UIImage?

    public init(
        usdzFile: String?,
        tone: AIPhotoTone = .sand,
        label: String? = nil,
        cornerRadius: CGFloat = 14,
        aspectRatio: CGFloat? = 4.0 / 3.0
    ) {
        self.usdzFile = usdzFile
        self.tone = tone
        self.label = label
        self.cornerRadius = cornerRadius
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        Group {
            if let thumbnail {
                rendered(thumbnail)
            } else {
                PhotoSlot(
                    tone: tone,
                    label: label,
                    cornerRadius: cornerRadius,
                    aspectRatio: aspectRatio
                )
                .task(id: usdzFile) {
                    thumbnail = await ModelThumbnailCache.shared.thumbnail(for: usdzFile)
                }
            }
        }
    }

    @ViewBuilder
    private func rendered(_ image: UIImage) -> some View {
        let content = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        if let aspectRatio {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            content
        }
    }
}

// MARK: - Кэш миниатюр

/// Однократный рендер миниатюры на имя файла; повторные запросы — из памяти.
actor ModelThumbnailCache {

    static let shared = ModelThumbnailCache()

    private var cache: [String: UIImage] = [:]
    private var failed: Set<String> = []

    func thumbnail(for usdzFile: String?) async -> UIImage? {
        guard let usdzFile, !usdzFile.isEmpty, !failed.contains(usdzFile) else { return nil }
        if let cached = cache[usdzFile] { return cached }

        let name = usdzFile.replacingOccurrences(of: ".usdz", with: "")

        // Сначала — предрендеренная миниатюра из бандла (детерминированно
        // и мгновенно; рендерится конвейером B1 на Mac вместе с USDZ).
        if let thumbURL = Bundle.main.url(forResource: "\(name)_thumb", withExtension: "png"),
           let data = try? Data(contentsOf: thumbURL),
           let image = UIImage(data: data) {
            cache[usdzFile] = image
            return image
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            failed.insert(usdzFile)
            return nil
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 480, height: 360),
            scale: 2,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            let image = representation.uiImage
            cache[usdzFile] = image
            return image
        } catch {
            failed.insert(usdzFile)
            return nil
        }
    }
}
