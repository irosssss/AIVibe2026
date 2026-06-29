// AIVibe/Features/ARDesigner/Assets/USDZLoader.swift
// L2: actor-загрузчик USDZ. Делает 3-tier резолюцию (network → bundle →
// placeholder-marker), кэширует на диск с LRU (200 MB). Возвращает Sendable
// USDZAsset (URL или placeholder-маркер). НЕ создаёт ModelEntity — это
// работа L3 FurnitureEntityFactory.

import Foundation
import CryptoKit
import Logging

/// Делегат URLSession, запрещающий следование HTTP-редиректам.
/// Защита от SSRF (E2): 302 мог бы увести с доверённого хоста каталога
/// на внутренний адрес уже после проверки isSafeRemoteHost.
private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public actor USDZLoader {

    private let diskCacheURL: URL
    private let logger = Logger(label: "ar.usdz-loader")
    private static let maxDiskCacheMB: Int = 200
    // Лимит на один скачиваемый USDZ (F4): потоковая загрузка обрывается на этом
    // размере, поэтому в памяти максимум maxFileBytes даже при заниженном/отсутствующем
    // Content-Length.
    private static let maxFileBytes: Int = 50 * 1_024 * 1_024

    // Allowlist хостов, с которых разрешено грузить USDZ (E2). Должен соответствовать
    // origin каталога — Yandex Object Storage, бакет aivibe-models (path-style
    // storage.yandexcloud.net и virtual-hosted <bucket>.storage.yandexcloud.net).
    // Позитивный allowlist закрывает SSRF через DNS-rebinding / *.nip.io: неизвестный
    // хост отвергается ДО резолва, как бы он ни резолвился. При смене CDN — дополнить.
    private static let allowedHostSuffixes: [String] = ["storage.yandexcloud.net"]

    // Сессия без следования редиректам (см. NoRedirectSessionDelegate).
    private let session = URLSession(
        configuration: .ephemeral,
        delegate: NoRedirectSessionDelegate(),
        delegateQueue: nil
    )

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
        guard let url = URL(string: remoteURL), isSafeRemoteHost(url) else {
            logger.warning("USDZ: небезопасный или некорректный URL — пропуск загрузки")
            return nil
        }

        let cacheKey = sha256(remoteURL)
        let localURL = diskCacheURL.appendingPathComponent("\(cacheKey).usdz")

        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        do {
            // session не следует редиректам (NoRedirectSessionDelegate) — иначе
            // 302 мог бы обойти isSafeRemoteHost.
            let (byteStream, response) = try await session.bytes(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "Не удалось загрузить USDZ: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                )
                return nil
            }
            // F4: ранний отказ по заявленному Content-Length — не читаем тело вовсе.
            if httpResponse.expectedContentLength > Int64(Self.maxFileBytes) {
                logger.warning("USDZ заявил размер больше лимита — пропуск")
                return nil
            }
            // Потоково накапливаем с жёстким обрывом на лимите: в памяти максимум
            // maxFileBytes, поэтому сервер, занизивший/опустивший Content-Length и
            // стримящий больше, обрывается по факту (выход из цикла отменяет загрузку).
            // Компромисс: побайтовое чтение; апгрейд при необходимости — чанковый делегат.
            var data = Data()
            data.reserveCapacity(min(Int(max(httpResponse.expectedContentLength, 0)), Self.maxFileBytes))
            for try await byte in byteStream {
                data.append(byte)
                if data.count > Self.maxFileBytes {
                    logger.warning("USDZ превысил лимит \(Self.maxFileBytes) Б при загрузке — обрыв")
                    return nil
                }
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

    /// SSRF-защита: грузим только по HTTPS и только с разрешённых хостов каталога.
    /// Позитивный allowlist (а не чёрный список приватных IP) надёжнее — он отвергает
    /// неизвестный хост ДО DNS-резолва, поэтому rebinding / *.nip.io не проходят.
    private func isSafeRemoteHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return Self.allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
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
