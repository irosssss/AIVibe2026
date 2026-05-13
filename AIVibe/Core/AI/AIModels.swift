// AIVibe/Core/AI/AIModels.swift
// Модуль: Core/AI
// Модели запросов и ответов для AI-провайдеров.

import Foundation

// MARK: - Сообщение чата

/// Сообщение для AI-чата. Единая модель для всех провайдеров.
public struct ChatMessage: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String

    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Промпт

/// Структурированный запрос к AI-провайдеру.
public struct AIPrompt: Sendable {
    public let messages: [ChatMessage]
    public let temperature: Double
    public let maxTokens: Int

    public init(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 1024
    ) {
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

// MARK: - Ответ

/// Унифицированный ответ от любого AI-провайдера.
public struct AIResponse: Sendable, Equatable {
    public let text: String
    public let providerName: String
    public let isOffline: Bool
    public let tokensUsed: Int

    public init(
        text: String,
        providerName: String,
        isOffline: Bool = false,
        tokensUsed: Int = 0
    ) {
        self.text = text
        self.providerName = providerName
        self.isOffline = isOffline
        self.tokensUsed = tokensUsed
    }
}
