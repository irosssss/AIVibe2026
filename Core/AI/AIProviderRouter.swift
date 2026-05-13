// Core/AI
// Модуль: Core
// Роутер провайдеров AI. Последовательное переключение при недоступности.

import Foundation

/// Протокол AI-провайдера. Все внешние зависимости — через протоколы.
public protocol AIProviderProtocol {
    /// Имя провайдера для логирования и мониторинга.
    var name: String { get }
    
    /// Доступен ли провайдер в текущей конфигурации.
    var isAvailable: Bool { get }
    
    /// Отправляет запрос к AI и получает ответ.
    func chat(
        messages: [ChatMessage],
        onCompletion: @escaping (Result<String, AIError>) -> Void
    )
    
    /// Асинхронная версия чата.
    func chat(messages: [ChatMessage]) async throws -> String
}

/// Сообщение для AI-чата.
public struct ChatMessage: Sendable, Identifiable, Codable {
    public let id: UUID
    public let role: Role
    public let content: String
    
    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }
    
    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// Ошибки AI-уровня.
public enum AIError: LocalizedError {
    case providerUnavailable(String)
    case invalidResponse
    case networkError(NetworkError)
    case modelError(String)
    case rateLimited
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let name):
            return "Провайдер недоступен: \(name)"
        case .invalidResponse:
            return "Некорректный ответ от AI"
        case .networkError(let error):
            return "Сетевая ошибка: \(error.localizedDescription)"
        case .modelError(let message):
            return "Ошибка модели: \(message)"
        case .rateLimited:
            return "Превышен лимит запросов"
        case .unknown(let error):
            return "Неизвестная ошибка: \(error.localizedDescription)"
        }
    }
}

/// Роутер AI-провайдеров. Переключается между провайдерами при недоступности.
public final class AIProviderRouter {
    private let providers: [any AIProviderProtocol]
    
    /// Создаёт роутер с указанным списком провайдеров.
    /// Провайдеры перечислены в порядке приоритета.
    public init(providers: [any AIProviderProtocol]) {
        self.providers = providers
    }
    
    /// Отправляет запрос через первый доступный провайдер.
    public func chat(
        messages: [ChatMessage],
        onCompletion: @escaping (Result<String, AIError>) -> Void
    ) {
        Task {
            do {
                let response = try await chat(messages: messages)
                onCompletion(.success(response))
            } catch let error as AIError {
                onCompletion(.failure(error))
            } catch {
                onCompletion(.failure(.unknown(error)))
            }
        }
    }
    
    /// Асинхронная версия с автоматическим переключением провайдеров.
    public func chat(messages: [ChatMessage]) async throws -> String {
        var lastError: AIError?
        
        for provider in providers {
            guard provider.isAvailable else { continue }
            
            do {
                let response = try await provider.chat(messages: messages)
                return response
            } catch let error as AIError {
                lastError = error
                continue
            } catch {
                lastError = .unknown(error)
                continue
            }
        }
        
        throw lastError ?? .providerUnavailable("Все провайдеры недоступны")
    }
}
