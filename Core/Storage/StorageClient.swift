// Core/Storage
// Модуль: Core
// Протокол клиента хранения и заглушка реализации.

import Foundation
import SwiftUI

/// Протокол хранилища. Покрыт моками для тестирования.
public protocol StorageClientProtocol {
    /// Сохраняет объект по ключу.
    func save<T: Codable>(_ value: T, forKey key: String) throws
    
    /// Загружает объект по ключу.
    func load<T: Codable>(forKey key: String) throws -> T?
    
    /// Удаляет объект по ключу.
    func remove(forKey key: String) throws
    
    /// Очищает всё хранилище.
    func clear() throws
}

/// Ошибки хранения.
public enum StorageError: LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileNotFound(String)
    case fileWriteFailed(Error)
    case permissionDenied
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            return "Ошибка сериализации: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Ошибка десериализации: \(error.localizedDescription)"
        case .fileNotFound(let key):
            return "Файл не найден: \(key)"
        case .fileWriteFailed(let error):
            return "Ошибка записи файла: \(error.localizedDescription)"
        case .permissionDenied:
            return "Нет доступа к хранилищу"
        case .unknown(let error):
            return "Неизвестная ошибка: \(error.localizedDescription)"
        }
    }
}

/// Реализация хранилища на основе UserDefaults + файловой системы.
public final class StorageClient: StorageClientProtocol {
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let storageDirectory: URL
    
    /// Создаёт клиент хранения.
    /// - Parameters:
    ///   - defaults: UserDefaults для небольших данных.
    ///   - fileManager: FileManager для файловых операций.
    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        storageDirectory: URL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AIVibeStorage")
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.storageDirectory = storageDirectory
        
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }
    
    public func save<T: Codable>(_ value: T, forKey key: String) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(key).dat")
        
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StorageError.fileWriteFailed(error)
        }
    }
    
    public func load<T: Codable>(forKey key: String) throws -> T? {
        let fileURL = storageDirectory.appendingPathComponent("\(key).dat")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw StorageError.decodingFailed(error)
        }
    }
    
    public func remove(forKey key: String) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(key).dat")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw StorageError.unknown(error)
        }
    }
    
    public func clear() throws {
        do {
            try fileManager.removeItem(at: storageDirectory)
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        } catch {
            throw StorageError.unknown(error)
        }
    }
}
