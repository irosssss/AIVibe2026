// AIVibe/App/DI/AppDependencies.swift
// Моду��ь: App
// Сборка live-зависимостей приложения.
// API-ключи получаются из переменных окружения (не хранятся в бандле).

import Foundation
import ComposableArchitecture

// MARK: - AppDependencies

public enum AppDependencies {

    /// Создаёт live-р��утер с реальными провайдерами.
    /// Вызывается один раз в AppEntry.swift при старте приложения.
    public static func prepareLiveRouter() -> AIProviderRouter {
        let providers: [any AIProviderProtocol] = [
            makeYandexGPT(),
            makeGigaChat(),
            CoreMLProvider()
        ]

        return AIProviderRouter(
            providers: providers,
            analytics: AppMetricaAnalytics()
        )
    }

    // MARK: - Фабрики провайдеров

    /// YandexGPT — IAM-токен + folderId из env
    private static func makeYandexGPT() -> YandexGPTProvider {
        let iamToken = ProcessInfo.processInfo.environment["YANDEX_IAM_TOKEN"] ?? ""
        let folderID = ProcessInfo.processInfo.environment["YANDEX_FOLDER_ID"] ?? ""
        return YandexGPTProvider(iamToken: iamToken, folderId: folderID)
    }

    /// GigaChat — clientSecret из env
    private static func makeGigaChat() -> GigaChatProvider {
        let clientSecret = ProcessInfo.processInfo.environment["GIGACHAT_CLIENT_SECRET"] ?? ""
        return GigaChatProvider(clientSecret: clientSecret)
    }
}
