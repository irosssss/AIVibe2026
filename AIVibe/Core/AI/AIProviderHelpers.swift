// AIVibe/Core/AI/AIProviderHelpers.swift
// Модуль: Core/AI
// Вспомогательные функции для AI-провайдеров:
// retry с exponential backoff, валидация HTTP, безопасный decode.

import Foundation

// MARK: - Retry

/// Выполняет async closure с повторами при ошибке (exponential backoff).
/// - Parameters:
///   - maxAttempts: максимальное число попыток (включая первую)
///   - baseDelay:   базовая задержка в секундах (удваивается при каждой попытке)
///   - operation:   асинхронная операция, которую нужно повторить
func withRetry<T: Sendable>(
    maxAttempts: Int,
    baseDelay: TimeInterval = 1.0,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch let error as AIError {
            // Не повторяем ошибки аутентификации и фильтрации контента
            switch error {
            case .authenticationFailed, .contentFiltered:
                throw error
            default:
                lastError = error
            }
        } catch {
            lastError = error
        }

        if attempt < maxAttempts - 1 {
            let delay = baseDelay * pow(2.0, Double(attempt))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    throw lastError ?? AIError.allProvidersExhausted
}

// MARK: - HTTP Validation

/// Проверяет HTTP-ответ и бросает типизированную AIError при ошибке.
func validateHTTP(response: URLResponse, provider: String) throws {
    guard let http = response as? HTTPURLResponse else {
        throw AIError.invalidResponse(provider: provider, details: "Не HTTPURLResponse")
    }

    switch http.statusCode {
    case 200...299:
        return
    case 401, 403:
        throw AIError.authenticationFailed(provider: provider)
    case 429:
        // Читаем Retry-After из заголовков если есть
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init)
        throw AIError.rateLimitExceeded(provider: provider, retryAfter: retryAfter)
    case 408, 504:
        throw AIError.timeout(provider: provider)
    case 503, 502:
        throw AIError.providerUnavailable(provider: provider)
    default:
        throw AIError.networkError(
            statusCode: http.statusCode,
            message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        )
    }
}

// MARK: - Safe Decode

/// Декодирует JSON с понятной AIError при провале.
func decode<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    provider: String
) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        throw AIError.invalidResponse(
            provider: provider,
            details: "JSON decode failed: \(error.localizedDescription). Raw: \(raw.prefix(200))"
        )
    }
}
