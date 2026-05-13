// AIVibe/App/DI/AppDependencies.swift
// Модуль: App
// Сборка live-зависимостей приложения.
// Здесь конфигурируются реальные провайдеры с параметрами из окружения.
// API-ключи и токены получаются через IAM/OAuth прокси, не хранятся в бандле.

import Foundation
import ComposableArchitecture

// MARK: - AppDependencies

public enum AppDependencies {

    /// Собирает и регистрирует все live-зависимости.
    /// Вызывается один раз при старте приложения в AIVibeApp.
    @MainActor
    public static func configure() {
        // Конфигурируем роутер через prepareLiveRouter()
        // Чтобы переопределить DependencyKey нужен custom DI-контейнер
        // При использовании TCA — через withDependencies в Scene
        _ = prepareLiveRouter()
    }

    /// Создаёт live-роутер с реальными провайдерами.
    public static func prepareLiveRouter() -> AIProviderRouter {
        let circuitBreaker = CircuitBreaker(
            config: CircuitBreaker.Configuration(
                failureThreshold: 3,
                cooldownDuration: 300, // 5 минут
                halfOpenTimeout:  60
            )
        )

        let providers: [any AIProviderProtocol] = [
            makeYandexGPT(),
            makeGigaChat(),
            CoreMLProvider()
        ]

        return AIProviderRouter(
            providers: providers,
            circuitBreaker: circuitBreaker,
            analytics: AppMetricaAnalytics(),
            healthCheckInterval: 60
        )
    }

    // MARK: - Фабрики провайдеров

    private static func makeYandexGPT() -> YandexGPTProvider {
        let folderID = ProcessInfo.processInfo.environment["YANDEX_FOLDER_ID"] ?? ""
        let config = YandexGPTProvider.Configuration(
            folderID: folderID,
            timeout: 30,
            maxRetries: 2
        )
        return YandexGPTProvider(
            config: config,
            tokenFetcher: BackendIAMTokenFetcher()
        )
    }

    private static func makeGigaChat() -> GigaChatProvider {
        let config = GigaChatProvider.Configuration(
            primaryModel:  "GigaChat-Max",
            fallbackModel: "GigaChat-Pro",
            timeout: 60,
            maxRetries: 2
        )
        return GigaChatProvider(
            config: config,
            tokenProvider: BackendGigaChatTokenProvider()
        )
    }
}

// MARK: - Backend Token Fetchers

/// Получает IAM-токен Yandex Cloud через backend-прокси.
/// Прокси сам получает и обновляет токены через сервисный аккаунт.
private struct BackendIAMTokenFetcher: IAMTokenFetching {
    private let backendURL: URL = {
        let urlStr = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"]
            ?? "https://api.aivibe.ru"
        return URL(string: urlStr + "/v1/auth/yandex-iam")!
    }()

    func fetchToken() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: backendURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.authenticationFailed(provider: "YandexGPT")
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.token
    }
}

/// Получает OAuth-токен GigaChat через backend-прокси.
private struct BackendGigaChatTokenProvider: GigaChatTokenProviding {
    private let backendURL: URL = {
        let urlStr = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"]
            ?? "https://api.aivibe.ru"
        return URL(string: urlStr + "/v1/auth/gigachat")!
    }()

    func fetchAccessToken() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: backendURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.authenticationFailed(provider: "GigaChat")
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.token
    }
}

/// Универсальная модель ответа токен-прокси.
private struct TokenResponse: Decodable {
    let token: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

// MARK: - AppMetrica Analytics

/// Реализация AnalyticsLogging через AppMetrica.
/// AppMetrica подключена через CocoaPods/бинарный фреймворк.
struct AppMetricaAnalytics: AnalyticsLogging {
    func log(event: String, params: [String: any Sendable]) {
        // AppMetrica.reportEvent(event, parameters: params as? [String: Any], onFailure: nil)
        // Раскомментировать после подключения AppMetrica SDK
    }
}
