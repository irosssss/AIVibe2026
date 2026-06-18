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
    // Лимит на один скачиваемый USDZ (F4): без него удалённый файл мог бы
    // исчерпать память. Компромисс: проверяем заявленный (Content-Length) и
    // фактический размер; сервер, лгущий о размере и стримящий больше, всё ещё
    // буферизуется URLSession. Путь апгрейда — потоковая загрузка с обрывом по байтам.
    private static let maxFileBytes: Int = 50 * 1_024 * 1_024

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
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "Не удалось загрузить USDZ: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                )
                return nil
            }
            // F4: отбрасываем слишком большой файл — по заголовку Content-Length
            // и по фактическому размеру.
            if httpResponse.expectedContentLength > Int64(Self.maxFileBytes)
                || data.count > Self.maxFileBytes {
                logger.warning("USDZ превышает лимит размера (\(data.count) Б) — пропуск")
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

    /// Допускаем только HTTPS и не приватный/loopback/link-local хост (защита от SSRF).
    private func isSafeRemoteHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return false }
        if Self.isPrivateOrReservedIP(host) { return false }
        return true
    }

    /// true, если host — IP-литерал из приватного/loopback/link-local/CGNAT диапазона.
    private static func isPrivateOrReservedIP(_ host: String) -> Bool {
        if host.contains(":") {
            // IPv6-литерал: для CDN-каталога нехарактерен → перестраховка, режем все.
            return true
        }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false } // домен, не IPv4-литерал
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        let oct0 = octets[0], oct1 = octets[1]
        if oct0 == 0 || oct0 == 127 || oct0 == 10 { return true }       // this-host / loopback / private
        if oct0 == 169 && oct1 == 254 { return true }                   // link-local
        if oct0 == 192 && oct1 == 168 { return true }                   // private
        if oct0 == 172 && (16...31).contains(oct1) { return true }      // private
        if oct0 == 100 && (64...127).contains(oct1) { return true }     // CGNAT
        return false
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
