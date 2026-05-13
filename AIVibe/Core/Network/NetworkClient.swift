// AIVibe/Core/Network/NetworkClient.swift
// Модуль: Core/Network
// HTTP-клиент на основе URLSession async/await (без Alamofire).
// Логирует каждый запрос через AIVibeLogger.network.
// Обрабатывает HTTP статусы: 401→authenticationFailed, 429→rateLimitExceeded, 5xx→serverError.

import Foundation
#if canImport(Logging)
import Logging
#endif

/// HTTP-клиент для взаим��действия с REST API.
// NOTE: @unchecked Sendable — URLSession и JSONDecoder thread-safe,
// все mutable поля (session, decoder, timeout) только для чтения.
public final class NetworkClient: @unchecked Sendable {

    // MARK: - Properties

    private let session: URLSession
    private let decoder: JSONDecoder
    private let timeout: TimeInterval

    #if canImport(Logging)
    private let logger = AIVibeLogger.network
    #endif

    // MARK: - Init

    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Public Methods

    /// GET-запрос с декодированием JSON-ответа.
    public func get<T: Decodable>(url: URL, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        applyHeaders(&request, headers)

        #if canImport(Logging)
        logger.info("GET \(url.absoluteString)")
        #endif

        let data = try await performRequest(request)
        return try decode(data)
    }

    /// POST-запрос с Encodable-телом и декодированием ответа.
    public func post<T: Decodable, B: Encodable>(url: URL, body: B, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(&request, headers)
        request.httpBody = try JSONEncoder().encode(body)

        #if canImport(Logging)
        logger.info("POST \(url.absoluteString)")
        #endif

        let data = try await performRequest(request)
        return try decode(data)
    }

    /// POST-запрос с сырыми Data и возвратом сырых Data.
    public func postRaw(url: URL, body: Data, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(&request, headers)
        request.httpBody = body

        #if canImport(Logging)
        logger.info("POST \(url.absoluteString) (raw)")
        #endif

        return try await performRequest(request)
    }

    // MARK: - Private

    private func applyHeaders(_ request: inout URLRequest, _ headers: [String: String]) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    /// Выполняет запрос и проверяет HTTP-статус.
    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            #if canImport(Logging)
            logger.error("URLSession error: \(error.localizedDescription)")
            #endif
            switch error.code {
            case .timedOut:
                throw NetworkError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noConnection
            default:
                throw NetworkError.httpError(statusCode: error.code.rawValue, data: Data())
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.httpError(statusCode: -1, data: data)
        }

        #if canImport(Logging)
        logger.info("→ HTTP \(httpResponse.statusCode)")
        #endif

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401:
            throw AIError.authenticationFailed(provider: "NetworkClient")
        case 429:
            throw AIError.rateLimitExceeded(provider: "NetworkClient", retryAfter: nil)
        case 500..<600:
            throw AIError.networkError(statusCode: httpResponse.statusCode, message: "Server error")
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Декодирует Data в Decodable тип.
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if canImport(Logging)
            logger.error("Decode failed: \(error.localizedDescription)")
            #endif
            throw NetworkError.decodingFailed(error)
        }
    }
}
