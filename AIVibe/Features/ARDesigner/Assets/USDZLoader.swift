// AIVibe/Features/ARDesigner/Assets/USDZLoader.swift
// L2: actor-загрузчик USDZ. Делает 3-tier резолюцию (network → bundle →
// placeholder-marker), кэширует на диск с LRU (200 MB). Возвращает Sendable
// USDZAsset (URL или placeholder-маркер). НЕ создаёт ModelEntity — это
// работа L3 FurnitureEntityFactory.

import Foundation
import CryptoKit
import Logging

public actor USDZLoader {

    private let diskCacheURL: URL
    private let logger = Logger(label: "ar.usdz-loader")
    private static let maxDiskCacheMB: Int = 200

    public init() {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        self.diskCacheURL = caches.appendingPathComponent("USDZCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: diskCacheURL, withIntermediateDirectories: true
        )
    }

    // MARK: - Public API

    /// 3-tier резолюция USDZ для item'а.
    public func resolveAsset(for item: FurnitureItem) async -> USDZAsset {
        // Tier 1: URL из сети
        if !item.usdzURL.isEmpty, item.usdzURL.hasPrefix("http") {
            if let url = await downloadIfNeeded(remoteURL: item.usdzURL) {
                return .file(url)
            }
        }

        // Tier 2: bundle по имени файла
        if !item.usdzURL.isEmpty, !item.usdzURL.hasPrefix("http") {
            if let url = bundleURL(for: item.usdzURL) {
                return .file(url)
            }
        }

        // Tier 2.5: bundle по типу мебели (generic каталог)
        if let url = bundleURL(for: item.itemType.lowercased()) {
            return .file(url)
        }

        // Tier 3: placeholder-маркер
        return .placeholder
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(
            at: diskCacheURL, withIntermediateDirectories: true
        )
    }

    // MARK: - Internal: network download + disk cache

    private func downloadIfNeeded(remoteURL: String) async -> URL? {
        guard let url = URL(string: remoteURL) else { return nil }

        let cacheKey = sha256(remoteURL)
        let localURL = diskCacheURL.appendingPathComponent("\(cacheKey).usdz")

        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "Не удалось загрузить USDZ: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                )
                return nil
            }
            try data.write(to: localURL)
            enforceDiskCacheLimit()
            return localURL
        } catch {
            logger.warning("Ошибка загрузки USDZ: \(error.localizedDescription)")
            return nil
        }
    }

    private func bundleURL(for filename: String) -> URL? {
        let name = filename.replacingOccurrences(of: ".usdz", with: "")
        return Bundle.main.url(forResource: name, withExtension: "usdz")
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func enforceDiskCacheLimit() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var totalSize: Int = 0
        var fileInfos: [(url: URL, date: Date, size: Int)] = []

        for file in files {
            guard let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { continue }
            totalSize += size
            fileInfos.append((file, date, size))
        }

        let maxBytes = Self.maxDiskCacheMB * 1_024 * 1_024
        guard totalSize > maxBytes else { return }

        fileInfos.sort { $0.date < $1.date }
        for info in fileInfos {
            try? fm.removeItem(at: info.url)
            totalSize -= info.size
            if totalSize <= maxBytes { break }
        }
    }
}
