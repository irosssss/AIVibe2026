// AIVibe/Core/AI/Connectors/ConnectorTypes.swift
// Общие типы коннекторов: идентификаторы и ошибки.
// Blueprint §10: Connectors — external systems.
//
// Пивот 2026-06 (docs/BUSINESS_MODEL.md): коннекторы маркетплейсов
// (Ozon/Wildberries) удалены — источник товаров один, каталог
// фабрик-партнёров через backend (functions/marketplace → YDB).

import Foundation

// MARK: - Connector ID

/// Идентификаторы внешних систем для health-мониторинга (`ConnectorHealthMonitor`).
public enum ConnectorID: String, Sendable, Codable, CaseIterable {
    /// Каталог фабрик-партнёров (backend aivibe-marketplace → YDB).
    case partnerCatalog = "partner_catalog"

    /// Человекочитаемое имя.
    public var displayName: String {
        switch self {
        case .partnerCatalog: return "Каталог фабрик-партнёров"
        }
    }

    /// Базовый URL API (партнёрский каталог доступен через наш backend).
    public var baseURL: String {
        switch self {
        case .partnerCatalog: return "https://functions.yandexcloud.net"
        }
    }
}

// MARK: - Connector Error

/// Ошибки взаимодействия с внешними системами.
public enum ConnectorError: LocalizedError, Sendable {
    case authFailed(String)
    case rateLimited(String)
    case networkFailed(String)
    case serverError(String)
    case httpError(statusCode: Int)
    case notConnected(String)

    public var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "Ошибка аутентификации: \(msg)"
        case .rateLimited(let msg): return "Превышен лимит запросов: \(msg)"
        case .networkFailed(let msg): return "Сетевая ошибка: \(msg)"
        case .serverError(let msg): return "Ошибка сервера: \(msg)"
        case .httpError(let code): return "HTTP ошибка: \(code)"
        case .notConnected(let name): return "Коннектор \(name) не подключён"
        }
    }
}
