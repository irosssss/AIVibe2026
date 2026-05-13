// AIVibeTests/AI/AIProviderRouterTests.swift
// Модуль: Tests
// Unit-тесты роутера AI-провайдеров.
// Покрывает: happy path, fallback-цепочку, Circuit Breaker, отсутствие сети.

import Testing
import Foundation
@testable import AIVibe

// MARK: - Mock Providers

/// Успешный мок-провайдер.
private struct SuccessProvider: AIProviderProtocol {
    let name: String
    let response: AIResponse
    var isAvailable: Bool { get async { true } }

    func complete(prompt: AIPrompt) async throws -> AIResponse { response }
}

/// Провайдер, который всегда падает.
private struct FailingProvider: AIProviderProtocol {
    let name: String
    let error: AIError
    var isAvailable: Bool { get async { true } }

    func complete(prompt: AIPrompt) async throws -> AIResponse { throw error }
}

/// Провайдер, который недоступен.
private struct UnavailableProvider: AIProviderProtocol {
    let name: String
    var isAvailable: Bool { get async { false } }

    func complete(prompt: AIPrompt) async throws -> AIResponse {
        throw AIError.providerUnavailable(provider: name)
    }
}

/// Провайдер, считающий количество вызовов.
private actor CountingProvider: AIProviderProtocol {
    nonisolated let name: String
    private(set) var callCount = 0
    private let shouldSucceedAfter: Int

    init(name: String, shouldSucceedAfter: Int = 0) {
        self.name = name
        self.shouldSucceedAfter = shouldSucceedAfter
    }

    nonisolated var isAvailable: Bool { get async { true } }

    func complete(prompt: AIPrompt) async throws -> AIResponse {
        callCount += 1
        if callCount > shouldSucceedAfter {
            return AIResponse(text: "ok", providerName: name, isOffline: false, tokensUsed: 1)
        }
        throw AIError.providerUnavailable(provider: name)
    }
}

// MARK: - Test Helpers

private func makePrompt(_ text: String = "Тест") -> AIPrompt {
    AIPrompt(messages: [ChatMessage(role: .user, content: text)])
}

// MARK: - Tests

@Suite("AIProviderRouter")
struct AIProviderRouterTests {

    // MARK: Happy Path

    @Test("Успешный ответ от первого провайдера")
    func test_firstProviderSuccess() async throws {
        let expected = AIResponse(text: "Ответ от YandexGPT", providerName: "YandexGPT", isOffline: false, tokensUsed: 10)
        let router = AIProviderRouter(
            providers: [SuccessProvider(name: "YandexGPT", response: expected)],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())

        #expect(result.text == expected.text)
        #expect(result.providerName == "YandexGPT")
        #expect(result.isOffline == false)
    }

    // MARK: Fallback Chain

    @Test("Fallback: пер��ый падает → второй отвечает")
    func test_fallbackToSecondProvider() async throws {
        let expected = AIResponse(text: "GigaChat ответил", providerName: "GigaChat", isOffline: false, tokensUsed: 20)
        let router = AIProviderRouter(
            providers: [
                FailingProvider(name: "YandexGPT", error: .providerUnavailable(provider: "YandexGPT")),
                SuccessProvider(name: "GigaChat", response: expected)
            ],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())

        #expect(result.providerName == "GigaChat")
        #expect(result.text == expected.text)
    }

    @Test("Triplex Fallback: первые два падают → CoreML отвечает оффлайн")
    func test_fallbackToCoreML() async throws {
        let offlineResponse = AIResponse(text: "Оффлайн совет", providerName: "CoreML", isOffline: true, tokensUsed: 0)
        let router = AIProviderRouter(
            providers: [
                FailingProvider(name: "YandexGPT", error: .networkUnavailable),
                FailingProvider(name: "GigaChat",  error: .networkUnavailable),
                SuccessProvider(name: "CoreML", response: offlineResponse)
            ],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())

        #expect(result.providerName == "CoreML")
        #expect(result.isOffline == true)
    }

    @Test("Все провайдеры исчерпаны → allProvidersExhausted")
    func test_allProvidersExhausted() async throws {
        let router = AIProviderRouter(
            providers: [
                FailingProvider(name: "YandexGPT", error: .networkUnavailable),
                FailingProvider(name: "GigaChat",  error: .networkUnavailable),
                FailingProvider(name: "CoreML",    error: .modelLoadingFailed("test"))
            ],
            analytics: NoopAnalytics()
        )

        await #expect(throws: AIError.self) {
            _ = try await router.complete(prompt: makePrompt())
        }
    }

    @Test("Пустой список провайдеров → ошибка")
    func test_emptyProviders() async throws {
        let router = AIProviderRouter(providers: [], analytics: NoopAnalytics())

        await #expect(throws: AIError.self) {
            _ = try await router.complete(prompt: makePrompt())
        }
    }

    // MARK: Circuit Breaker

    @Test("Circuit Breaker: провайдер пропускается после failureThreshold провалов")
    func test_circuitBreakerOpensAfterThreshold() async throws {
        let cb = CircuitBreaker(config: .init(failureThreshold: 3, cooldownDuration: 3600))

        // Записываем 3 провала вручную
        await cb.recordFailure(provider: "YandexGPT")
        await cb.recordFailure(provider: "YandexGPT")
        await cb.recordFailure(provider: "YandexGPT")

        let allowed = await cb.isAllowed(provider: "YandexGPT")
        #expect(allowed == false)
    }

    @Test("Circuit Breaker: сброс после успеха")
    func test_circuitBreakerResetsOnSuccess() async throws {
        let cb = CircuitBreaker(config: .init(failureThreshold: 2))

        await cb.recordFailure(provider: "GigaChat")
        await cb.recordFailure(provider: "GigaChat")
        var allowed = await cb.isAllowed(provider: "GigaChat")
        #expect(allowed == false)

        await cb.recordSuccess(provider: "GigaChat")
        allowed = await cb.isAllowed(provider: "GigaChat")
        #expect(allowed == true)
    }

    @Test("Circuit Breaker: открытый провайдер пропускается в роутере")
    func test_routerSkipsOpenCircuitBreaker() async throws {
        let cb = CircuitBreaker(config: .init(failureThreshold: 1, cooldownDuration: 3600))
        await cb.recordFailure(provider: "YandexGPT") // Открываем breaker

        let successResponse = AIResponse(text: "ok", providerName: "GigaChat", isOffline: false, tokensUsed: 5)
        let router = AIProviderRouter(
            providers: [
                FailingProvider(name: "YandexGPT", error: .providerUnavailable(provider: "YandexGPT")),
                SuccessProvider(name: "GigaChat", response: successResponse)
            ],
            circuitBreaker: cb,
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())
        // YandexGPT пропущен (breaker открыт) → GigaChat ответил
        #expect(result.providerName == "GigaChat")
    }

    @Test("Circuit Breaker: cooldownRemaining возвращает положительное время")
    func test_cooldownRemaining() async throws {
        let cb = CircuitBreaker(config: .init(failureThreshold: 1, cooldownDuration: 300))
        await cb.recordFailure(provider: "YandexGPT")

        let remaining = await cb.cooldownRemaining(provider: "YandexGPT")
        #expect(remaining > 0)
        #expect(remaining <= 300)
    }

    // MARK: No Network

    @Test("Нет сети: все облачные падают → CoreML оффлайн")
    func test_noNetworkFallsBackToOffline() async throws {
        let offlineResponse = AIResponse(
            text: "Совет без сети",
            providerName: "CoreML",
            isOffline: true,
            tokensUsed: 0
        )
        let router = AIProviderRouter(
            providers: [
                FailingProvider(name: "YandexGPT", error: .networkUnavailable),
                FailingProvider(name: "GigaChat",  error: .networkUnavailable),
                SuccessProvider(name: "CoreML", response: offlineResponse)
            ],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())
        #expect(result.isOffline == true)
        #expect(result.providerName == "CoreML")
    }

    // MARK: AIError

    @Test("AIError: rateLimitExceeded содержит имя провайдера")
    func test_rateLimitError() {
        let error = AIError.rateLimitExceeded(provider: "YandexGPT", retryAfter: 30)
        #expect(error.errorDescription?.contains("YandexGPT") == true)
        #expect(error.errorDescription?.contains("30") == true)
    }

    @Test("AIError: circuitBreakerOpen содержит cooldown")
    func test_circuitBreakerError() {
        let error = AIError.circuitBreakerOpen(provider: "GigaChat", cooldown: 120)
        #expect(error.errorDescription?.contains("120") == true)
    }

    @Test("AIError: Equatable работает корректно")
    func test_errorEquatable() {
        #expect(AIError.networkUnavailable == AIError.networkUnavailable)
        #expect(AIError.allProvidersExhausted == AIError.allProvidersExhausted)
        #expect(
            AIError.providerUnavailable(provider: "A") != AIError.providerUnavailable(provider: "B")
        )
    }
}
