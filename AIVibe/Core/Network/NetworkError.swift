// AIVibe/Core/Network/NetworkError.swift
// Модуль: Core/Network
// Ошибки сетевого уровня.

import Foundation

/// Ошибки, возникающие при выполнении HTTP-запросов.
public enum NetworkError: LocalizedError, Sendable {
    case invalidURL
    case httpError(statusCode: Int, data: Data)
    case decodingFailed(Error)
    case timeout
    case noConnection

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный URL"
        case .httpError(let statusCode, _):
            return "HTTP \(statusCode)"
        case .decodingFailed(let error):
            return "Ошибка декодирования: \(error.localizedDescription)"
        case .timeout:
            return "Таймаут запроса"
        case .noConnection:
            return "Нет подключения к интернету"
        }
    }
}
