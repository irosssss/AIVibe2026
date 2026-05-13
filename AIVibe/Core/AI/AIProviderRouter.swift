// AIVibe/Core/AI/AIProviderRouter.swift
// Модуль: Core/AI
// Главный роутер AI-провайдеров. Triplex Fallback: YandexGPT → GigaChat → CoreML.
// Содержит Circuit Breaker, логирование в AppMetrica, фоновый health-check.

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
/// Если провайдер падает `failureThreshold` раз подряд —
/// Circuit Breaker пропускает его на `cooldownDuration`.
public final class AIProviderRouter: Sendable {

    // MARK: - Dependencies

    private let providers: [any AIProviderProtocol]
    private let circuitBreaker: CircuitBreaker
    private let analytics: AnalyticsLogging
    private let logger = Logger(label: "ai.router")

    // Фоновый health-check task
    private let healthCheckTask: Task<Void, Never>

    // MARK: - Init

    public init(
        providers: [any AIProviderProtocol],
        circuitBreaker: CircuitBreaker = CircuitBreaker(),
        analytics: AnalyticsLogging = NoopAnalytics(),
        healthCheckInterval: TimeInterval = 60
    ) {
        self.providers      = providers
        self.circuitBreaker = circuitBreaker
        self.analytics      = analytics

        // Фоновый health-check: каждые healthCheckInterval секунд
        // проверяем провайдеры и сбрасываем breaker если они снова живы
        let cbRef = circuitBreaker
        let logRef = Logger(label: "ai.router.health")
        let providersCopy = providers

        healthCheckTask = Task.detached(priority: .background) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                for provider in providersCopy {
                    let allowed = await cbRef.isAllowed(provider: provider.name)
                    guard !allowed else { continue } // Пропускаем открытые (уже в cooldown)

                    let available = await provider.isAvailable
                    if available {
                        await cbRef.reset(provider: provider.name)
                        logRef.info("💚 Health-check: \(provider.name) снова доступен")
                    }
                }
            }
        }
    }

    deinit {
        healthCheckTask.cancel()
    }

    // MARK: - Public API

    /// Выполняет запрос через первый доступный провайдер.
    /// Логирует каждый fallback в аналитику.
    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        var lastError: Error?

        for provider in providers {
            // Проверяем Circuit Breaker
            let allowed = await circuitBreaker.isAllowed(provider: provider.name)
            guard allowed else {
                let cooldown = await circuitBreaker.cooldownRemaining(provider: provider.name)
                logger.info("⏸️ Пропускаем \(provider.name): Circuit Breaker открыт ещё \(Int(cooldown))с")
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

            do {
                logger.info("🔄 Пробуем провайдер: \(provider.name)")
                let response = try await provider.complete(prompt: prompt)

                // Успех — сбрасываем Circuit Breaker
                await circuitBreaker.recordSuccess(provider: provider.name)

                analytics.log(
                    event: "ai_request_success",
                    params: [
                        "provider": provider.name,
                        "offline": response.isOffline,
                        "tokens": response.tokensUsed
                    ]
                )

                return response

            } catch {
                lastError = error
                logger.warning("❌ \(provider.name) вернул ошибку: \(error)")

                // Записываем провал в Circuit Breaker
                await circuitBreaker.recordFailure(provider: provider.name)

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

    /// Анализирует изображение через первый поддерживающий провайдер.
    public func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse {
        var lastError: Error?

        for provider in providers {
            let allowed = await circuitBreaker.isAllowed(provider: provider.name)
            guard allowed else { continue }

            do {
                let response = try await provider.analyzeImage(imageData, prompt: prompt)
                await circuitBreaker.recordSuccess(provider: provider.name)
                return response
            } catch AIError.providerUnavailable {
                // Этот провайдер не поддерживает vision — идём дальше без записи провала
                continue
            } catch {
                lastError = error
                await circuitBreaker.recordFailure(provider: provider.name)
            }
        }

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
