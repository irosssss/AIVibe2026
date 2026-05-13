// AIVibe/Core/AI/AIProviderRouter.swift
// Модуль: Core/AI
// Гла��ный роутер AI-провайдеров. Triplex Fallback: YandexGPT → GigaChat → CoreML.
// Circuit Breaker для каждого провайдера, логирование в AppMetrica.

import Foundation
import Logging
import ComposableArchitecture

// MARK: - AIProviderRouter

/// Роутер AI-провайдеров с Triplex Fallback логикой.
///
/// Порядок попыток:
/// 1. YandexGPT 5  (основной)
/// 2. GigaChat-Max (резервный)
/// 3. Core ML      (оффлайн)
///
/// Если провайдер падает `threshold` раз подряд —
/// Circuit Breaker пропускает его на `timeout` секунд.
public actor AIProviderRouter {

    // MARK: - Dependencies

    private let providers: [any AIProviderProtocol]
    internal var breakers: [String: CircuitBreaker] = [:]
    private let analytics: AnalyticsLogging
    private let logger = Logger(label: "ai.router")

    // MARK: - Init

    public init(
        providers: [any AIProviderProtocol],
        analytics: AnalyticsLogging = NoopAnalytics()
    ) {
        self.providers = providers
        self.analytics = analytics

        // Создаём Circuit Breaker для каждого провайдера
        for provider in providers {
            breakers[provider.name] = CircuitBreaker()
        }
    }

    // MARK: - Public API

    /// Выполняет запрос через первый доступный провайдер.
    /// Логирует каждый fallback в аналитику.
    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        try await routeRequest { provider in
            try await provider.complete(prompt: prompt)
        }
    }

    /// Анализирует изображение через первый поддерживающий провайдер.
    public func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse {
        try await routeRequest { provider in
            try await provider.analyzeImage(imageData, prompt: prompt)
        }
    }

    // MARK: - Private: Generic Router

    /// Обобщённый метод маршрутизации.
    /// - Параметр `operation`: замыкание, выполняемое на каждом провайдере.
    /// - Triplex Fallback: пробует каждого по очереди.
    /// - Circuit Breaker: если открыт — пропускает провайдера.
    /// - Каждый fallback логируется в аналитику.
    /// - Возвращает результат первого успешного провайдера.
    /// - Если все провайдеры исчерпаны — бросает `allProvidersExhausted`.
    private func routeRequest<T>(
        _ operation: (any AIProviderProtocol) async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for provider in providers {
            // 1. Проверяем Circuit Breaker
            let breaker = breakers[provider.name] ?? CircuitBreaker()
            let allowed = await breaker.canRequest()

            guard allowed else {
                let cooldown = breaker.cooldownRemaining
                logger.info("⏸️  Пропускаем \(provider.name): Circuit Breaker открыт ещё \(Int(cooldown))с")
                analytics.log(
                    event: "ai_circuit_breaker_skip",
                    params: ["provider": provider.name, "cooldown": cooldown]
                )
                lastError = AIError.circuitBreakerOpen(
                    provider: provider.name,
                    cooldown: cooldown
                )
                continue
            }

            // 2. Выполняем запрос
            do {
                logger.info("🔄 Пробуем провайдер: \(provider.name)")
                let result = try await operation(provider)

                // Успех — сбрасываем Circuit Breaker
                await breaker.recordSuccess()

                analytics.log(
                    event: "ai_request_success",
                    params: ["provider": provider.name]
                )

                return result

            } catch AIError.providerUnavailable {
                // Провайдер не поддерживает операцию (например, vision) — идём дальше без записи провала
                logger.info("⏩ \(provider.name): не поддерживает эту операцию")
                lastError = error
                continue

            } catch {
                lastError = error
                logger.warning("❌ \(provider.name) вернул ошибку: \(error.localizedDescription)")

                // Записываем провал в Circuit Breaker
                await breaker.recordFailure()

                analytics.log(
                    event: "ai_provider_fallback",
                    params: [
                        "from_provider": provider.name,
                        "error": error.localizedDescription
                    ]
                )
            }
        }

        // Все провайдеры исчерпаны
        analytics.log(event: "ai_all_providers_exhausted", params: [:])
        throw lastError ?? AIError.allProvidersExhausted
    }
}

// MARK: - Analytics Protocol

/// Протокол аналитики. Позволяет подменять AppMetrica в тестах.
public protocol AnalyticsLogging: Sendable {
    func log(event: String, params: [String: any Sendable])
}

/// Заглушка аналитики для тестов и Preview.
public struct NoopAnalytics: AnalyticsLogging {
    public init() {}
    public func log(event: String, params: [String: any Sendable]) {}
}

// MARK: - TCA Dependency

extension DependencyValues {
    public var aiRouter: AIProviderRouter {
        get { self[AIProviderRouterKey.self] }
        set { self[AIProviderRouterKey.self] = newValue }
    }
}

private enum AIProviderRouterKey: DependencyKey {
    static let liveValue: AIProviderRouter = {
        // Live-значение собирается в App/DI/AppDependencies.swift
        // Здесь возвращаем пустой роутер как placeholder
        AIProviderRouter(providers: [])
    }()

    static let testValue: AIProviderRouter = {
        AIProviderRouter(providers: [])
    }()

    static let previewValue: AIProviderRouter = {
        AIProviderRouter(providers: [MockAIProvider()])
    }()
}

// MARK: - Mock Provider (Preview/Tests)

/// Мок-провайдер для Preview и тестов.
public struct MockAIProvider: AIProviderProtocol {
    public let name = "Mock"
    public var isAvailable: Bool { get async { true } }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        AIResponse(
            text: "Мок-ответ: \(prompt.messages.last?.content ?? "")",
            providerName: name,
            isOffline: false,
            tokensUsed: 42
        )
    }
}
