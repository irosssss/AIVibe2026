// AIVibe/Core/AI/Providers/GigaChatProvider.swift
// Модуль: Core/AI
// Провайдер GigaChat (Сбер). Endpoint: gigachat.devices.sberbank.ru
// Auth: OAuth-токен получается через backend-прокси.
// GigaChat использует самоподписанный сертификат Сбербанка — обрабатывается через делегат.
// Docs: https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/post-chat

import Foundation
import CryptoKit
import Logging

// MARK: - Token Provider Protocol

/// Протокол получения OAuth-токена GigaChat.
/// Токен запрашивается с backend-прокси, не напрямую из приложения.
public protocol GigaChatTokenProviding: Sendable {
    func fetchAccessToken() async throws -> String
}

// MARK: - GigaChat API Models (private)

private struct GigaChatRequest: Encodable {
    let model: String
    let messages: [GigaMessage]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }

    struct GigaMessage: Encodable {
        let role: String
        let content: String
    }
}

private struct GigaChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage
    let model: String

    struct Choice: Decodable {
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens     = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens      = "total_tokens"
        }
    }
}

// MARK: - Certificate Delegate

/// Handles Sberbank's TLS certificate with public-key pinning (SHA-256).
/// When `pinnedHashes` contains the placeholder value, pinning is *disabled*
/// and the delegate falls back to default evaluation — this is safe because
/// default evaluation still validates the certificate chain against the OS
/// trust store.  Replace the placeholder with real SHA-256 hashes of
/// Sberbank's public keys before shipping to production.
private final class SberCertificateDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    /// SHA-256 hashes of Sberbank certificate public keys.
    /// Update when the certificate rotates.
    /// Set via environment or remote config in production.
    private let pinnedHashes: Set<String> = {
        if let envHashes = ProcessInfo.processInfo.environment["SBER_CERT_HASHES"] {
            return Set(envHashes.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        return ["SBER_CERT_HASH_PLACEHOLDER"]
    }()

    /// Whether real pinning is configured (no placeholder values).
    private var isPinningConfigured: Bool {
        !pinnedHashes.contains("SBER_CERT_HASH_PLACEHOLDER") && !pinnedHashes.isEmpty
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // If pinning is not configured, use default OS evaluation (still validates chain).
        guard isPinningConfigured else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Extract public key from the leaf certificate and compute SHA-256 hash.
        guard
            SecTrustGetCertificateCount(serverTrust) > 0,
            let certificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
            let leafCert = certificate.first,
            let publicKey = SecCertificateCopyKey(leafCert),
            let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let hash = sha256Hex(publicKeyData)

        if pinnedHashes.contains(hash) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // Hash mismatch — possible MITM.
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Computes SHA-256 hex digest of data using CryptoKit.
    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - GigaChatProvider

/// Провайдер GigaChat. Цепочка: GigaChat-Max → GigaChat-Pro (внутренний fallback).
public final class GigaChatProvider: AIProviderProtocol {

    // MARK: - Конфигурация

    public struct Configuration: Sendable {
        let primaryModel: String
        let fallbackModel: String
        let timeout: TimeInterval
        let maxRetries: Int

        public init(
            primaryModel: String  = "GigaChat-Max",
            fallbackModel: String = "GigaChat-Pro",
            timeout: TimeInterval = 60, // GigaChat может отвечать медленнее
            maxRetries: Int       = 2
        ) {
            self.primaryModel  = primaryModel
            self.fallbackModel = fallbackModel
            self.timeout       = timeout
            self.maxRetries    = maxRetries
        }
    }

    // MARK: - Properties

    public let name = "GigaChat"

    private let config: Configuration
    private let tokenProvider: any GigaChatTokenProviding
    private let session: URLSession
    private let logger = Logger(label: "ai.gigachat")

    private static let endpoint = URL(
        string: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"
    )!

    // MARK: - Init

    public init(
        config: Configuration = .init(),
        tokenProvider: any GigaChatTokenProviding
    ) {
        self.config        = config
        self.tokenProvider = tokenProvider

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest  = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 3

        // Кастомный делегат для самоподписанного сертификата Сбербанка
        self.session = URLSession(
            configuration: sessionConfig,
            delegate: SberCertificateDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - AIProviderProtocol

    public var isAvailable: Bool {
        get async {
            var req = URLRequest(url: Self.endpoint)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 5
            do {
                let (_, response) = try await session.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return code != 0
            } catch {
                return false
            }
        }
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        do {
            return try await send(prompt: prompt, model: config.primaryModel)
        } catch {
            logger.warning("GigaChat Max failed, trying Pro: \(error)")
            return try await send(prompt: prompt, model: config.fallbackModel)
        }
    }

    // MARK: - Private

    private func send(prompt: AIPrompt, model: String) async throws -> AIResponse {
        let token = try await tokenProvider.fetchAccessToken()

        let body = GigaChatRequest(
            model: model,
            messages: prompt.messages.map {
                GigaChatRequest.GigaMessage(role: $0.role.rawValue, content: $0.content)
            },
            stream: false,
            temperature: prompt.temperature,
            maxTokens: prompt.maxTokens
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Уникальный ID запроса для дедупликации на стороне Сбера
        request.setValue(UUID().uuidString,  forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(body)

        return try await withRetry(maxAttempts: config.maxRetries) { [self] in
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response: response, provider: name)

            let decoded = try decode(GigaChatResponse.self, from: data, provider: name)

            guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
                throw AIError.invalidResponse(provider: name, details: "Пустой choices[0].message.content")
            }

            let tokens = decoded.usage.totalTokens
            logger.info("GigaChat ответил, модель: \(model), токены: \(tokens)")

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

public extension GigaChatProvider {
    /// Стриминг ответа GigaChat через SSE.
    func stream(prompt: AIPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try await tokenProvider.fetchAccessToken()

                    let body = GigaChatRequest(
                        model: config.primaryModel,
                        messages: prompt.messages.map {
                            GigaChatRequest.GigaMessage(role: $0.role.rawValue, content: $0.content)
                        },
                        stream: true,
                        temperature: prompt.temperature,
                        maxTokens: prompt.maxTokens
                    )

                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(UUID().uuidString,  forHTTPHeaderField: "X-Request-ID")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    try validateHTTP(response: response, provider: name)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard jsonStr != "[DONE]",
                              let data = jsonStr.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GigaChatResponse.self, from: data),
                              let text = chunk.choices.first?.message.content
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
