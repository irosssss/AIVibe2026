// AIVibe/Core/AI/Connectors/LockBoxSecretsManager.swift
// Stage 5: Yandex LockBox secrets manager + ConnectorHealthMonitor.
// Blueprint §10: Yandex Lockbox auth, connector health.

import Foundation
import Logging

// MARK: - LockBox Secrets Manager

/// Менеджер секретов через Yandex LockBox.
///
/// Хранит API ключи, OAuth токены, client secrets для всех внешних систем.
///
/// Blueprint §10:
/// ```
/// connector: wildberries_api
/// auth: Yandex Lockbox (API key)
///
/// connector: ozon_api
/// auth: Yandex Lockbox (API key + Client-ID)
/// ```
public actor LockBoxSecretsManager {

    // MARK: - Secret Keys

    /// Ключи секретов в LockBox.
    public enum SecretKey: String, Sendable, CaseIterable {
        case wildberriesApiKey = "WB_API_KEY"
        case ozonApiKey = "OZON_API_KEY"
        case ozonClientId = "OZON_CLIENT_ID"
        case yandexIamToken = "YANDEX_IAM_TOKEN"
        case yandexFolderId = "YANDEX_FOLDER_ID"
        case gigachatClientSecret = "GIGACHAT_CLIENT_SECRET"
        case appToken = "APP_TOKEN"
    }

    // MARK: - State

    /// Кэш секретов в памяти (ключ = SecretKey.rawValue).
    private var cache: [String: String] = [:]

    /// Флаг: использовать локальный .env файл вместо LockBox (для разработки).
    private let useLocalEnv: Bool

    /// Логгер.
    private let logger = Logger(label: "ai.lockbox")

    // MARK: - Init

    /// - Parameter useLocalEnv: Если `true` — читает секреты из локального `.env`-файла (dev),
    ///   иначе — через Yandex LockBox API.
    public init(useLocalEnv: Bool = true) {
        self.useLocalEnv = useLocalEnv
    }

    // MARK: - Public API

    /// Получает значение секрета по ключу.
    /// - Parameter key: Ключ секрета (из `SecretKey`).
    /// - Returns: Значение секрета или `nil`, если не найден.
    public func getSecret(_ key: SecretKey) async -> String? {
        // Проверяем кэш
        if let cached = cache[key.rawValue] {
            return cached
        }

        let value: String?

        if useLocalEnv {
            // Локальная разработка: читаем из process environment
            value = ProcessInfo.processInfo.environment[key.rawValue]
        } else {
            // Продакшн: запрос к Yandex LockBox API
            value = await fetchFromLockBox(key)
        }

        if let value = value {
            cache[key.rawValue] = value
            logger.debug("🔑 Секрет загружен: \(key.rawValue)")
        } else {
            logger.warning("⚠️ Секрет не найден: \(key.rawValue)")
        }

        return value
    }

    /// Получает API ключ (удобный alias).
    public func getApiKey(_ key: SecretKey) async -> String? {
        await getSecret(key)
    }

    /// Получает OAuth токен (удобный alias).
    public func getOAuthToken(_ key: SecretKey) async -> String? {
        await getSecret(key)
    }

    /// Получает Client Secret (удобный alias).
    public func getClientSecret(_ key: SecretKey) async -> String? {
        await getSecret(key)
    }

    /// Очищает кэш секретов.
    public func clearCache() {
        cache.removeAll()
        logger.info("🗑️ Кэш секретов очищен")
    }

    /// Предзагружает все известные секреты в кэш.
    public func preloadAll() async {
        for key in SecretKey.allCases {
            _ = await getSecret(key)
        }
        logger.info("📦 Секреты предзагружены: \(cache.count)/\(SecretKey.allCases.count)")
    }

    /// Проверяет доступность LockBox.
    public func isAvailable() async -> Bool {
        if useLocalEnv { return true }
        // Пробный запрос к LockBox
        return await fetchFromLockBox(.appToken) != nil
    }

    // MARK: - Private

    /// Запрос к Yandex LockBox API.
    private func fetchFromLockBox(_ key: SecretKey) async -> String? {
        // Yandex LockBox REST API:
        // GET https://lockbox.api.cloud.yandex.net/lockbox/v1/secrets/{secretId}
        // Требует IAM токен в заголовке Authorization: Bearer {iamToken}

        // В MVP: возвращаем nil (используем локальные переменные окружения)
        // Продакшн реализация будет добавлена при деплое в Yandex Cloud
        logger.debug("🔒 LockBox fetch: \(key.rawValue) — используем локальный env")
        return nil
    }
}

// MARK: - Environment Helper

/// Хелпер для чтения секретов из `.env`-файла (локальная разработка).
/// Используется `LockBoxSecretsManager(useLocalEnv: true)`.
public enum EnvironmentLoader {

    /// Загружает переменные из `.env`-файла в корне проекта.
    /// Формат файла: `KEY=VALUE`, одна пара на строку.
    /// Игнорирует пустые строки и строки, начинающиеся с `#`.
    public static func loadDotEnv(path: String = ".env") {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            Darwin.setenv(key, value, 1)
        }
    }

    /// Устанавливает одну переменную окружения.
    public static func setenv(_ name: String, _ value: String) {
        Darwin.setenv(name, value, 1)
    }
}

// MARK: - Connector Health Monitor

/// Мониторит здоровье всех внешних коннекторов.
///
/// Blueprint §10: отслеживание Circuit Breaker для коннекторов.
///
/// Каждый коннектор имеет:
/// - `isOnline` — доступен ли API
/// - `lastCheck` — время последней проверки
/// - `consecutiveFailures` — счётчик ошибок подряд
/// - `cooldownUntil` — до какого времени пропускать запросы
public actor ConnectorHealthMonitor {

    // MARK: - State

    /// Состояние каждого коннектора.
    private var health: [ConnectorID: ConnectorHealthState] = [:]

    /// Максимальное число ошибок подряд до отключения.
    private let maxFailures: Int

    /// Время охлаждения после отключения (секунды).
    private let cooldownSeconds: TimeInterval

    /// Логгер.
    private let logger = Logger(label: "ai.connectors.health")

    // MARK: - Init

    public init(maxFailures: Int = 3, cooldownSeconds: TimeInterval = 300) {
        self.maxFailures = maxFailures
        self.cooldownSeconds = cooldownSeconds
    }

    // MARK: - Public API

    /// Проверяет здоровье коннектора.
    public func healthCheck(_ connector: ConnectorID) async {
        var state = health[connector] ?? ConnectorHealthState(connector: connector)

        // Проверяем, не в охлаждении ли
        if state.cooldownUntil != nil {
            if Date() >= state.cooldownUntil! {
                // Охлаждение закончилось — пробуем восстановить
                state.cooldownUntil = nil
                state.consecutiveFailures = 0
                state.isOnline = true
                logger.info("🔄 \(connector.displayName): восстановлен после охлаждения")
            } else {
                // Ещё в охлаждении — пропускаем
                return
            }
        }

        state.lastCheck = Date()
        health[connector] = state
    }

    /// Отмечает успешный запрос к коннектору.
    public func recordSuccess(_ connector: ConnectorID) {
        var state = health[connector] ?? ConnectorHealthState(connector: connector)
        state.consecutiveFailures = 0
        state.isOnline = true
        state.lastCheck = Date()
        health[connector] = state
    }

    /// Отмечает ошибку коннектора.
    public func recordFailure(_ connector: ConnectorID) {
        var state = health[connector] ?? ConnectorHealthState(connector: connector)
        state.consecutiveFailures += 1
        state.lastCheck = Date()

        if state.consecutiveFailures >= maxFailures {
            state.isOnline = false
            state.cooldownUntil = Date().addingTimeInterval(cooldownSeconds)
            logger.warning("🔴 \(connector.displayName): отключён после \(state.consecutiveFailures) ошибок (охлаждение до \(state.cooldownUntil!.formatted(.iso8601)))")
        }

        health[connector] = state
    }

    /// Проверяет, здоров ли коннектор.
    public func isHealthy(_ connector: ConnectorID) -> Bool {
        guard let state = health[connector] else {
            return true  // Нет данных — считаем здоровым
        }
        return state.isOnline
    }

    /// Возвращает статус коннектора для `ConnectorStatus`.
    public func status(_ connector: ConnectorID) -> ConnectorStatus {
        guard let state = health[connector] else {
            return .online
        }

        if state.cooldownUntil != nil, Date() < state.cooldownUntil! {
            return .offline
        }
        if state.consecutiveFailures > 0 {
            return .degraded
        }
        return state.isOnline ? .online : .offline
    }

    /// Возвращает все состояния.
    public func allStates() -> [ConnectorID: ConnectorHealthState] {
        health
    }

    /// Сбрасывает состояние коннектора.
    public func reset(_ connector: ConnectorID) {
        health[connector] = ConnectorHealthState(connector: connector)
        logger.info("🔄 \(connector.displayName): сброшен")
    }
}

// MARK: - Connector Health State

/// Состояние здоровья одного коннектора.
public struct ConnectorHealthState: Sendable, Codable {
    /// Идентификатор коннектора.
    public let connector: String

    /// Доступен ли API.
    public var isOnline: Bool

    /// Время последней проверки.
    public var lastCheck: Date?

    /// Число последовательных ошибок.
    public var consecutiveFailures: Int

    /// До какого времени коннектор в охлаждении (nil = не в охлаждении).
    public var cooldownUntil: Date?

    public init(
        connector: ConnectorID,
        isOnline: Bool = true,
        lastCheck: Date? = nil,
        consecutiveFailures: Int = 0,
        cooldownUntil: Date? = nil
    ) {
        self.connector = connector.rawValue
        self.isOnline = isOnline
        self.lastCheck = lastCheck
        self.consecutiveFailures = consecutiveFailures
        self.cooldownUntil = cooldownUntil
    }
}
