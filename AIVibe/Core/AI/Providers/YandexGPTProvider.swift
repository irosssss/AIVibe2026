// AIVibe/Core/AI/Providers/YandexGPTProvider.swift
// Модуль: Core/AI
// Провайдер YandexGPT 5. Endpoint: llm.api.cloud.yandex.net
// Auth: IAM-токен получается через backend-прокси, не хранится в приложении.
// Docs: https://yandex.cloud/ru/docs/foundation-models/concepts/yandexgpt/models

import Foundation
import Logging

// MARK: - IAM Token Fetcher Protocol

/// Протокол получения IAM-токена Yandex Cloud.
/// Реализация запрашивает токен с backend-прокси (никогда не из app напрямую).
public protocol IAMTokenFetching: Sendable {
    func fetchToken() async throws -> String
}

// MARK: - YandexGPT API Models (private)

private struct YandexGPTRequest: Encodable {
    let modelUri: String
    let completionOptions: CompletionOptions
    let messages: [YandexMessage]

    struct CompletionOptions: Encodable {
        let stream: Bool
        let temperature: Double
        let maxTokens: String // API принимает строку
    }

    struct YandexMessage: Encodable {
        let role: String
        let text: String
    }
}

private struct YandexGPTResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let alternatives: [Alternative]
        let usage: Usage
        let modelVersion: String?
    }

    struct Alternative: Decodable {
        let message: Message
        let status: String
    }

    struct Message: Decodable {
        let role: String
        let text: String
    }

    struct Usage: Decodable {
        let inputTextTokens: String
        let completionTokens: String
        let totalTokens: String
    }
}

// MARK: - YandexGPTProvider

/// Провайдер YandexGPT 5 / YandexGPT 5 Lite.
/// Triplex: если основная модель недоступна — пробует lite внутри провайдера.
public final class YandexGPTProvider: AIProviderProtocol {

    // MARK: - Конфигурация

    public struct Configuration: Sendable {
        /// URI основной модели. Формат: gpt://{folder_id}/yandexgpt-5
        let primaryModelURI: String
        /// URI лёгкой модели. Формат: gpt://{folder_id}/yandexgpt-5-lite
        let fallbackModelURI: String
        let timeout: TimeInterval
        let maxRetries: Int

        public init(
            folderID: String,
            timeout: TimeInterval = 30,
            maxRetries: Int = 2
        ) {
            self.primaryModelURI  = "gpt://\(folderID)/yandexgpt-5"
            self.fallbackModelURI = "gpt://\(folderID)/yandexgpt-5-lite"
            self.timeout    = timeout
            self.maxRetries = maxRetries
        }
    }

    // MARK: - Properties

    public let name = "YandexGPT"

    private let config: Configuration
    private let tokenFetcher: any IAMTokenFetching
    private let session: URLSession
    private let logger = Logger(label: "ai.yandexgpt")

    private static let endpoint = URL(
        string: "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
    )!

    // MARK: - Init

    public init(
        config: Configuration,
        tokenFetcher: any IAMTokenFetching,
        session: URLSession = .shared
    ) {
        self.config       = config
        self.tokenFetcher = tokenFetcher

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest  = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - AIProviderProtocol

    public var isAvailable: Bool {
        get async {
            // Проверяем достижимость endpoint HEAD-запросом
            var req = URLRequest(url: Self.endpoint)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 5
            do {
                let (_, response) = try await session.data(for: req)
                // 401 допустим — значит сервер отвечает
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return code != 0
            } catch {
                return false
            }
        }
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        // Пробуем основную модель, при ошибке — lite
        do {
            return try await send(prompt: prompt, modelURI: config.primaryModelURI)
        } catch {
            logger.warning("YandexGPT primary failed, trying lite: \(error)")
            return try await send(prompt: prompt, modelURI: config.fallbackModelURI)
        }
    }

    // MARK: - Private

    private func send(prompt: AIPrompt, modelURI: String) async throws -> AIResponse {
        let token = try await tokenFetcher.fetchToken()

        let body = YandexGPTRequest(
            modelUri: modelURI,
            completionOptions: .init(
                stream: false,
                temperature: prompt.temperature,
                maxTokens: String(prompt.maxTokens)
            ),
            messages: prompt.messages.map {
                YandexGPTRequest.YandexMessage(role: $0.role.rawValue, text: $0.content)
            }
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)",   forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        return try await withRetry(maxAttempts: config.maxRetries) { [self] in
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response: response, provider: name)

            let decoded = try decode(YandexGPTResponse.self, from: data, provider: name)

            guard let text = decoded.result.alternatives.first?.message.text else {
                throw AIError.invalidResponse(provider: name, details: "Пустой список alternatives")
            }

            let tokens = Int(decoded.result.usage.totalTokens) ?? 0
            logger.info("YandexGPT ответил, модель: \(modelURI), токены: \(tokens)")

            return AIResponse(
                text: text,
                providerName: name,
                isOffline: false,
                tokensUsed: tokens
            )
        }
    }
}

// MARK: - Streaming Extension (SSE)

public extension YandexGPTProvider {
    /// Стриминг ответа через SSE. Возвращает AsyncThrowingStream токенов.
    func stream(prompt: AIPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try await tokenFetcher.fetchToken()
                    let body = YandexGPTRequest(
                        modelUri: config.primaryModelURI,
                        completionOptions: .init(
                            stream: true,
                            temperature: prompt.temperature,
                            maxTokens: String(prompt.maxTokens)
                        ),
                        messages: prompt.messages.map {
                            YandexGPTRequest.YandexMessage(role: $0.role.rawValue, text: $0.content)
                        }
                    )

                    let streamEndpoint = URL(
                        string: "https://llm.api.cloud.yandex.net/foundationModels/v1/completion/stream"
                    )!
                    var request = URLRequest(url: streamEndpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    try validateHTTP(response: response, provider: name)

                    // Читаем SSE строки
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard jsonStr != "[DONE]",
                              let data = jsonStr.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(YandexGPTResponse.self, from: data),
                              let text = chunk.result.alternatives.first?.message.text
                        else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
