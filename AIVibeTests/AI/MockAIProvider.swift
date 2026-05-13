// AIVibeTests/AI/MockAIProvider.swift
// Модуль: Tests
// Мок-провайдеры для unit-тестов AIProviderRouter.
//
// Содержит:
// - MockAIProviderSuccess — возвращает предустановленный ответ
// - MockAIProviderFailure — всегда бросает заданную ошибку
// - MockAIProviderCounting — считает количество вызовов, успешен после N провалов

import Foundation
@testable import AIVibe

// MARK: - MockAIProviderSuccess

/// Провайдер, который всегда успешно возвращает предустановленный ответ.
public struct MockAIProviderSuccess: AIProviderProtocol {
    public let name: String
    public let response: AIResponse
    public var isAvailable: Bool { get async { true } }

    public init(name: String, response: AIResponse) {
        self.name = name
        self.response = response
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        response
    }
}

// MARK: - MockAIProviderFailure

/// Провайдер, который всегда бросает заданную ошибку.
public struct MockAIProviderFailure: AIProviderProtocol {
    public let name: String
    public let error: AIError
    public var isAvailable: Bool { get async { true } }

    public init(name: String, error: AIError) {
        self.name = name
        self.error = error
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        throw error
    }
}

// MARK: - MockAIProviderCounting

/// Провайдер, считающий количество вызовов.
/// Падает `shouldFailTimes` раз, затем начинает успешно отвечать.
public actor MockAIProviderCounting: AIProviderProtocol {
    public nonisolated let name: String
    public private(set) var callCount = 0
    private let shouldSucceedAfter: Int
    private let successResponse: AIResponse

    public nonisolated var isAvailable: Bool { get async { true } }

    public init(
        name: String,
        shouldSucceedAfter: Int = 0,
        successResponse: AIResponse = AIResponse(
            text: "ok",
            providerName: "MockCounting",
            isOffline: false,
            tokensUsed: 1
        )
    ) {
        self.name = name
        self.shouldSucceedAfter = shouldSucceedAfter
        self.successResponse = successResponse
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        callCount += 1
        if callCount > shouldSucceedAfter {
            return successResponse
        }
        throw AIError.providerUnavailable(provider: name)
    }
}
