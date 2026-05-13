// Core/Network
// Модуль: Core
// Протокол HTTP-клиента. Позволяет мокировать сетевой слой при тестировании.

import Foundation

/// Протокол сетевого клиента. Все внешние зависимости — через протоколы.
public protocol NetworkClientProtocol {
    /// Выполняет GET-запрос и декодирует ответ в указанный тип.
    func get<T: Decodable>(
        url: URL,
        responseType: T.Type,
        completion: @escaping (Result<T, NetworkError>) -> Void
    )
    
    /// Выполняет GET-запрос в async/await стиле.
    func get<T: Decodable>(
        url: URL,
        responseType: T.Type
    ) async throws -> T
}

/// Ошибки сетевого уровня. Кастомный enum с associated values.
public enum NetworkError: LocalizedError {
    case invalidURL
    case noData
    case decodingFailed(Error)
    case httpError(statusCode: Int, message: String)
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .noData:
            return "Данные не получены"
        case .decodingFailed(let error):
            return "Ошибка декодирования: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP ошибка \(statusCode): \(message)"
        case .unknown(let error):
            return "Неизвестная ошибка: \(error.localizedDescription)"
        }
    }
}

/// Реализация сетевого клиента поверх URLSession.
public final class NetworkClient: NetworkClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    /// Создаёт клиент с кастомным URLSession или стандартным.
    public init(
        session: URLSession = .shared,
        decoder: JSONDecoder = .init()
    ) {
        self.session = session
        self.decoder = decoder
    }
    
    public func get<T: Decodable>(
        url: URL,
        responseType: T.Type,
        completion: @escaping (Result<T, NetworkError>) -> Void
    ) {
        Task {
            do {
                let result = try await get(url: url, responseType: T.self)
                completion(.success(result))
            } catch let error as NetworkError {
                completion(.failure(error))
            } catch {
                completion(.failure(.unknown(error)))
            }
        }
    }
    
    public func get<T: Decodable>(
        url: URL,
        responseType: T.Type
    ) async throws -> T {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String),
        ].compactMap { $0 }
        
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: finalURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(NSError(domain: "NetworkClient", code: -1))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        guard !data.isEmpty else {
            throw NetworkError.noData
        }
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
}
