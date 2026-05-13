// AIVibe/Core/AI/AIError.swift
// Модуль: Core/AI
// Перечисление ошибок AI-подсистемы с ассоциированными значениями.

import Foundation

/// Ошибки AI-уровня. Используются во всех провайдерах и роутере.
public enum AIError: LocalizedError, Sendable, Equatable {
    case networkUnavailable
    case providerUnavailable(provider: String)
    case rateLimitExceeded(provider: String, retryAfter: TimeInterval?)
    case invalidResponse(provider: String, details: String)
    case allProvidersExhausted
    case offlineModeActive
    case contentFiltered(reason: String)
    case modelLoadingFailed(String)
    case circuitBreakerOpen(provider: String, cooldown: TimeInterval)
    case networkError(statusCode: Int, message: String)
    case authenticationFailed(provider: String)
    case timeout(provider: String)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Нет подключения к интернету"
        case .providerUnavailable(let provider):
            return "Провайдер \(provider) недоступен"
        case .rateLimitExceeded(let provider, let retryAfter):
            let suffix = retryAfter.map { ", повтор через \(Int($0))с" } ?? ""
            return "Лимит запросов для \(provider) превышен\(suffix)"
        case .invalidResponse(let provider, let details):
            return "Некорректный ответ от \(provider): \(details)"
        case .allProvidersExhausted:
            return "Все AI-провайдеры недоступны"
        case .offlineModeActive:
            return "Работает оффлайн-режим"
        case .contentFiltered(let reason):
            return "Контент отфильтрован: \(reason)"
        case .modelLoadingFailed(let model):
            return "Ошибка загрузки модели: \(model)"
        case .circuitBreakerOpen(let provider, let cooldown):
            return "\(provider) временно отключён (повтор через \(Int(cooldown))с)"
        case .networkError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .authenticationFailed(let provider):
            return "Ошибка аутентификации: \(provider)"
        case .timeout(let provider):
            return "Таймаут запроса к \(provider)"
        }
    }
}
