// AIVibe/Core/AI/AIProvider.swift
// Модуль: Core/AI
// Протокол AI-провайдера. Все реализации должны быть Sendable.

import Foundation

/// Базовый протокол для AI-провайдеров.
/// Каждый провайдер реализует работу с конкретным API (YandexGPT, GigaChat, CoreML).
public protocol AIProviderProtocol: Sendable {
    /// Имя провайдера для логирования и аналитики.
    var name: String { get }

    /// Проверяет доступность провайдера (сеть, токены, модель загружена).
    var isAvailable: Bool { get async }

    /// Отправляет промпт и возвращает ответ.
    func complete(prompt: AIPrompt) async throws -> AIResponse

    /// Анализирует изображение (для провайдеров с vision API).
    /// По умолчанию — выбрасывает ошибку "не поддерживается".
    func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse
}

// MARK: - Default Implementation

public extension AIProviderProtocol {
    func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse {
        throw AIError.providerUnavailable(provider: "\(name): analyzeImage не поддерживается")
    }
}
