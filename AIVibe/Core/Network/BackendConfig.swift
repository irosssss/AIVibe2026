// AIVibe/Core/Network/BackendConfig.swift
// Модуль: Core/Network
// Конфигурация живого бэкенда (Yandex Cloud Functions).
//
// Источники значений (по приоритету):
//   1. Info.plist (ключи AIVibe*) — путь для CI/xcconfig-инжекции (L5/#22);
//   2. BackendConfig.plist в бандле — локальные сборки разработчика.
//      Файл в .gitignore (репозиторий публичный, токен и URL не коммитим);
//      образец — BackendConfig.example.plist рядом.
//
// Значение не задано ни там, ни там → фича деградирует (чат отвечает
// демо-моком, каталог — стабом), приложение не падает.

import Foundation

public enum BackendConfig {

    /// URL Cloud Function ai-advisor (AI-чат + дизайн-пайплайн).
    public static var aiAdvisorURL: URL? { url(forKey: "AIVibeAIAdvisorURL") }

    /// URL Cloud Function marketplace (поиск каталога + резолвер артикулов B3).
    public static var marketplaceURL: URL? { url(forKey: "AIVibeMarketplaceURL") }

    /// App Token — заголовок X-App-Token (#14/#20).
    public static var appToken: String? { value(forKey: "AIVibeAppToken") }

    /// Заголовки авторизации для всех вызовов бэкенда.
    public static var authHeaders: [String: String] {
        guard let token = appToken else { return [:] }
        return ["X-App-Token": token]
    }

    /// Бэкенд сконфигурирован (есть куда ходить и чем подписываться).
    public static var isConfigured: Bool {
        aiAdvisorURL != nil && appToken != nil
    }

    // MARK: - Чтение

    private static func url(forKey key: String) -> URL? {
        value(forKey: key).flatMap(URL.init(string:))
    }

    private static func value(forKey key: String) -> String? {
        if let fromInfo = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !fromInfo.isEmpty {
            return fromInfo
        }
        if let fromLocal = localPlist[key], !fromLocal.isEmpty {
            return fromLocal
        }
        return nil
    }

    /// BackendConfig.plist из бандла (локальная конфигурация разработчика).
    /// Только строковые значения — Sendable для Swift 6 concurrency.
    private static let localPlist: [String: String] = {
        guard let url = Bundle.main.url(forResource: "BackendConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: String] else {
            return [:]
        }
        return plist
    }()
}
