// AIVibeTests/AI/AIProviderRouterTests.swift
// Модуль: Tests
// Unit-тесты роутера AI-провайдеров.
// Покрывает: happy path, fallback-цепочку, Circuit Breaker, отсутствие сети.

import Testing
import Foundation
@testable import AIVibe

// MARK: - Test Helpers

private func makePrompt(_ text: String = "Тест") -> AIPrompt {
    AIPrompt(messages: [ChatMessage(role: .user, content: text)])
}

private func makeResponse(
    text: String = "response",
    providerName: String = "YandexGPT",
    isOffline: Bool = false,
    tokensUsed: Int = 0
) -> AIResponse {
    AIResponse(text: text, providerName: providerName, isOffline: isOffline, tokensUsed: tokensUsed)
}

// MARK: - Tests

@Suite("AIProviderRouter")
struct AIProviderRouterTests {

    // MARK: Happy Path

    @Test("Успешный ответ от первого провайдера — второй не вызывается")
    func test_primaryProviderSucceeds_noFallback() async throws {
        let primary = MockAIProviderCounting(
            name: "YandexGPT",
            shouldSucceedAfter: 0,
            successResponse: makeResponse(text: "Ответ YandexGPT", providerName: "YandexGPT")
        )
        let secondary = MockAIProviderCounting(
            name: "GigaChat",
            shouldSucceedAfter: 999,
            successResponse: makeResponse(text: "GigaChat", providerName: "GigaChat")
        )

        let router = AIProviderRouter(
            providers: [primary, secondary],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())

        #expect(result.text == "Ответ YandexGPT")
        #expect(result.providerName == "YandexGPT")

        let primaryCount = await primary.callCount
        let secondaryCount = await secondary.callCount
        #expect(primaryCount == 1)
        #expect(secondaryCount == 0, "Второй провайдер не должен вызываться при успехе первого")
    }

    // MARK: Fallback Chain

    @Test("Первый провайдер падает → второй отвечает (fallback)")
    func test_primaryFails_fallsBackToSecondary() async throws {
        let primary = MockAIProviderFailure(name: "YandexGPT", error: .providerUnavailable(provider: "YandexGPT"))
        let secondary = MockAIProviderSuccess(
            name: "GigaChat",
            response: makeResponse(text: "Ответ GigaChat", providerName: "GigaChat")
        )

        let router = AIProviderRouter(
            providers: [primary, secondary],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())

        #expect(result.providerName == "GigaChat")
        #expect(result.text == "Ответ GigaChat")
        #expect(result.isOffline == false)
    }

    @Test("Первые два падают → третий (CoreML) отвечает оффлайн")
    func test_allCloudFail_fallsBackToOffline() async throws {
        let cloud1 = MockAIProviderFailure(name: "YandexGPT", error: .networkUnavailable)
        let cloud2 = MockAIProviderFailure(name: "GigaChat", error: .networkUnavailable)
        let offline = MockAIProviderSuccess(
            name: "CoreML",
            response: makeResponse(text: "Оффлайн совет", providerName: "CoreML", isOffline: true)
        )

        let router = AIProviderRouter(
            providers: [cloud1, cloud2, offline],
            analytics: NoopAnalytics()
        )

        let result = try await router.complete(prompt: makePrompt())

        #expect(result.providerName == "CoreML")
        #expect(result.isOffline == true)
        #expect(result.text == "Оффлайн совет")
    }

    @Test("Все провайдеры падают → allProvidersExhausted")
    func test_allProvidersFail_throwsAllProvidersExhausted() async throws {
        let router = AIProviderRouter(
            providers: [
                MockAIProviderFailure(name: "YandexGPT", error: .networkUnavailable),
                MockAIProviderFailure(name: "GigaChat", error: .rateLimitExceeded(provider: "GigaChat", retryAfter: nil)),
                MockAIProviderFailure(name: "CoreML", error: .modelLoadingFailed("test.mlmodel"))
            ],
            analytics: NoopAnalytics()
        )

        await #expect(throws: AIError.self) {
            _ = try await router.complete(prompt: makePrompt())
        }
    }

    @Test("Пустой список провайдеров → allProvidersExhausted")
    func test_emptyProviders() async throws {
        let router = AIProviderRouter(providers: [], analytics: NoopAnalytics())

        await #expect(throws: AIError.self) {
            _ = try await router.complete(prompt: makePrompt())
        }
    }

    // MARK: Circuit Breaker

    @Test("Circuit Breaker открыт → провайдер пропускается, идём к следующему")
    func test_circuitBreakerOpen_providerSkipped() async throws {
        let primary = MockAIProviderFailure(name: "YandexGPT", error: .providerUnavailable(provider: "YandexGPT"))
        let secondary = MockAIProviderSuccess(
            name: "GigaChat",
            response: makeResponse(text: "GigaChat ответил", providerName: "GigaChat")
        )

        let router = AIProviderRouter(
            providers: [primary, secondary],
            analytics: NoopAnalytics()
        )

        // Симулируем 3 провала YandexGPT → Circuit Breaker откроется
        for _ in 0..<3 {
            let cb = router.breakers["YandexGPT"]!
            await cb.recordFailure()
        }

        // Теперь YandexGPT должен быть пропущен, GigaChat ответит
        let result = try await router.complete(prompt: makePrompt())
        #expect(result.providerName == "GigaChat")
        #expect(result.text == "GigaChat ответил")
    }

    @Test("Circuit Breaker сбрасывается после успеха")
    func test_circuitBreakerResetsOnSuccess() async throws {
        let cb = CircuitBreaker(threshold: 2, timeout: 3600)

        await cb.recordFailure()
        await cb.recordFailure()
        #expect(await cb.canRequest() == false)

        await cb.recordSuccess()
        #expect(await cb.canRequest() == true)
    }

    @Test("Circuit Breaker сбрасывается после таймаута (cooldown истекает)")
    func test_circuitBreakerResetsAfterTimeout() async throws {
        let cb = CircuitBreaker(threshold: 2, timeout: 0.001)

        await cb.recordFailure()
        await cb.recordFailure()

        #expect(await cb.canRequest() == false)

        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(await cb.canRequest() == true)
    }

    @Test("Circuit Breaker: cooldownRemaining > 0")
    func test_cooldownRemaining() async throws {
        let cb = CircuitBreaker(threshold: 1, timeout: 300)

        await cb.recordFailure()
        let remaining = await cb.cooldownRemaining
        #expect(remaining > 0)
        #expect(remaining <= 300)
    }

    // MARK: AIError

    @Test("AIError: rateLimitExceeded содержит имя провайдера и retryAfter")
    func test_rateLimitErrorDescription() {
        let error = AIError.rateLimitExceeded(provider: "YandexGPT", retryAfter: 30)
        #expect(error.errorDescription?.contains("YandexGPT") == true)
        #expect(error.errorDescription?.contains("30") == true)
    }

    @Test("AIError: circuitBreakerOpen содержит cooldown")
    func test_circuitBreakerErrorDescription() {
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
