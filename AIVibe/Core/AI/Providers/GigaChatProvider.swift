// AIVibe/Core/AI/Providers/GigaChatProvider.swift
// Модуль: Core/AI/Providers
// Провайдер GigaChat (Сбер).

import Foundation

// MARK: - Token Storage Actor

/// Actor для безопасного хранения и кэширования OAuth-токена GigaChat.
private actor GigaChatTokenStore {
    private(set) var accessToken: String?
    private var expiryDate: Date?

    /// Сохраняет токен с TTL 29 минут.
    func store(token: String) {
        self.accessToken = token
        // Токен живёт 30 мин, кэшируем на 29 для безопасности
        self.expiryDate = Date().addingTimeInterval(29 * 60)
    }

    /// Возвращает кэшированный токен если он не истёк.
    func cachedToken() -> String? {
        guard let token = accessToken,
              let expiry = expiryDate,
              Date() < expiry else {
            return nil
        }
        return token
    }

    /// Сбрасывает кэш (например, при ошибке 401).
    func invalidate() {
        accessToken = nil
        expiryDate = nil
    }
}

// MARK: - URLSession Delegate for Self-Signed Certificate

/// Делегат сессии для работы с самоподписанным сертификатом GigaChat.
///
/// ⚠️ ТОЛЬКО ДЛЯ РАЗРАБОТКИ. В продакшене использовать pinned certificate
/// через `SecCertificateCreateWithData` и проверку в этом методе.
/// См.: https://developer.apple.com/documentation/security/certificate_key_and_trust_services/validating_a_certificate
private final class GigaChatSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Принимаем любой сертификат — только для dev окружения GigaChat
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let credential = URLCredential(trust: trust)
        completionHandler(.useCredential, credential)
    }
}

// MARK: - GigaChat Provider

/// Провайдер для GigaChat API (Сбер).
/// Документация: https://developers.sber.ru/docs/ru/gigachat/api/chat-completion
public final class GigaChatProvider: AIProviderProtocol, Sendable {

    // MARK: - Properties

    public let name: String = "GigaChat"

    private let clientSecret: String
    private let tokenStore = GigaChatTokenStore()

    private static let authURLString = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"
    private static let chatURLString = "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"

    /// Сессия с кастомным делегатом для самоподписанного сертификата.
    private let session: URLSession

    // MARK: - Init

    /// Инициализирует провайдер GigaChat.
    /// - Parameter clientSecret: Client Secret авторизации GigaChat (OAuth).
    public init(clientSecret: String) {
        self.clientSecret = clientSecret

        let delegate = GigaChatSessionDelegate()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - AIProviderProtocol

    public var isAvailable: Bool {
        get async {
            guard let url = URL(string: Self.chatURLString) else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"

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
        let token = try await getValidToken()

        guard let chatURL = URL(string: Self.chatURLString) else {
            throw AIError.invalidResponse(provider: name, details: "Неверный URL чата")
        }

        // Формируем сообщения в формате OpenAI-совместимого API GigaChat
        let messages: [[String: String]] = prompt.messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let requestBody: [String: Any] = [
            "model": "GigaChat-Max",
            "messages": messages,
            "temperature": prompt.temperature,
            "max_tokens": prompt.maxTokens
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIError.invalidResponse(provider: name, details: "Не удалось сериализовать запрос")
        }

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 25

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkUnavailable
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data: data)
        case 401, 403:
            // Инвалидируем кэш токена при проблемах с аутентификацией
            await tokenStore.invalidate()
            throw AIError.authenticationFailed(provider: name)
        case 429:
            throw AIError.rateLimitExceeded(provider: name, retryAfter: nil)
        case 500...599:
            throw AIError.networkError(statusCode: httpResponse.statusCode, message: "Server error")
        default:
            throw AIError.networkError(statusCode: httpResponse.statusCode, message: "Unexpected status")
        }
    }

    // MARK: - OAuth

    /// Получает валидный OAuth-токен (из кэ��а или запрашивает новый).
    private func getValidToken() async throws -> String {
        // Проверяем кэш
        if let cached = await tokenStore.cachedToken() {
            return cached
        }

        // Запрашиваем новый токен
        let newToken = try await fetchOAuthToken()
        await tokenStore.store(token: newToken)
        return newToken
    }

    /// Выполняет OAuth запрос к API GigaChat.
    private func fetchOAuthToken() async throws -> String {
        guard let authURL = URL(string: Self.authURLString) else {
            throw AIError.invalidResponse(provider: name, details: "Неверный URL авторизации")
        }

        let requestBody: [String: String] = [
            "scope": "GIGACHAT_API_PERS"
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIError.invalidResponse(provider: name, details: "Ошибка тела OAuth запроса")
        }

        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkUnavailable
        }

        guard httpResponse.statusCode == 200 else {
            // Ошибка OAuth → authenticationFailed
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.invalidResponse(provider: name, details: "OAuth ошибка \(httpResponse.statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw AIError.invalidResponse(provider: name, details: "Нет access_token в ответе OAuth")
        }

        return accessToken
    }

    // MARK: - Private

    /// Парсит ответ от GigaChat Chat Completions API.
    /// Ожидаемый формат: { "choices": [{ "message": { "content": "..." } }] }
    private func parseResponse(data: Data) throws -> AIResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse(provider: name, details: "Невалидный JSON")
        }

        // Пробуем стандартный OpenAI-формат
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return AIResponse(text: content, providerName: name)
        }

        // Fallback — пробуем извлечь текст из других возможных форматов
        if let alternatives = json["alternatives"] as? [[String: Any]],
           let firstAlt = alternatives.first,
           let message = firstAlt["message"] as? [String: Any],
           let content = message["content"] as? String {
            return AIResponse(text: content, providerName: name)
        }

        throw AIError.invalidResponse(
            provider: name,
            details: "Не удалось распарсить ответ: \(json)"
        )
    }
}
