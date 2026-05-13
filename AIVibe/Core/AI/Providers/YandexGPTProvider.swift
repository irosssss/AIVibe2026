// AIVibe/Core/AI/Providers/YandexGPTProvider.swift
// Модуль: Core/AI/Providers
// Провайдер YandexGPT (Yandex Cloud Foundation Models).

import Foundation

// MARK: - YandexGPT Provider

/// Провайдер для YandexGPT API.
/// Документация: https://cloud.yandex.ru/docs/yandexgpt/
public final class YandexGPTProvider: AIProviderProtocol, Sendable {

    // MARK: - Properties

    public let name: String = "YandexGPT"

    private let iamToken: String
    private let folderId: String
    private let endpointURL: URL
    private let session: URLSession

    /// Модельный URI в формате gpt://{folderId}/yandexgpt-5/latest
    private var modelURI: String {
        "gpt://\(folderId)/yandexgpt-5/latest"
    }

    // MARK: - Init

    /// Инициализирует провайдер YandexGPT.
    /// - Parameters:
    ///   - iamToken: IAM-токен для аутентификации в Yandex Cloud.
    ///   - folderId: ID папки в Yandex Cloud.
    public init(iamToken: String, folderId: String) {
        self.iamToken = iamToken
        self.folderId = folderId
        self.endpointURL = URL(string: "https://llm.api.cloud.yandex.net/foundationModels/v1/completion")!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
    }

    // MARK: - AIProviderProtocol

    public var isAvailable: Bool {
        get async throws {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "HEAD"
            request.setValue("Bearer \(iamToken)", forHTTPHeaderField: "Authorization")

            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    return false
                }
                return httpResponse.statusCode < 500
            } catch {
                return false
            }
        }
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        // Формируем тело запроса по спецификации YandexGPT API
        let messages: [[String: String]] = prompt.messages.map { msg in
            ["role": msg.role.rawValue, "text": msg.content]
        }

        let requestBody: [String: Any] = [
            "modelUri": modelURI,
            "completionOptions": [
                "temperature": prompt.temperature,
                "maxTokens": prompt.maxTokens
            ],
            "messages": messages
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIError.invalidResponse(provider: name, details: "Не удалось сериализовать запрос")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(iamToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 25

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data: data)
        case 429:
            throw AIError.rateLimitExceeded(provider: name, retryAfter: nil)
        case 401, 403:
            throw AIError.authenticationFailed(provider: name)
        case 500...599:
            throw AIError.networkError(statusCode: httpResponse.statusCode, message: "Server error")
        default:
            throw AIError.networkError(statusCode: httpResponse.statusCode, message: "Unexpected status")
        }
    }

    // MARK: - Private

    /// Парсит ответ от YandexGPT API.
    /// Ожидаемый формат: { "result": { "alternatives": [{ "message": { "content": "..." } }] } }
    private func parseResponse(data: Data) throws -> AIResponse {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let alternatives = result["alternatives"] as? [[String: Any]],
                  let firstAlternative = alternatives.first,
                  let message = firstAlternative["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                // Пробуем формат choices[0].message.content (универсальный fallback)
                return try parseChoicesFormat(data: data)
            }

            return AIResponse(
                text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                providerName: name,
                isOffline: false
            )
        } catch {
            return try parseChoicesFormat(data: data)
        }
    }

    /// Парсинг формата choices[0].message.content (OpenAI-совместимый).
    private func parseChoicesFormat(data: Data) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            throw AIError.invalidResponse(provider: name, details: "Не удалось распарсить ответ: \(raw.prefix(200))")
        }

        return AIResponse(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            providerName: name,
            isOffline: false
        )
    }
}
