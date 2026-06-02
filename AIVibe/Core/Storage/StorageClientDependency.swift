// AIVibe/Core/Storage/StorageClientDependency.swift
// TCA-регистрация StorageClient + in-memory реализация для тестов/preview.
// Вынесено из StorageClient.swift, чтобы не тащить ComposableArchitecture
// в чистый Foundation-модуль хранилища.

import ComposableArchitecture
import Foundation

private enum StorageClientKey: DependencyKey {
    /// Live — файловое хранилище в Caches.
    static let liveValue: any StorageClientProtocol = StorageClient()
    /// Test/preview — без записи на диск, изолированное между тестами.
    static var testValue: any StorageClientProtocol { InMemoryStorageClient() }
    static var previewValue: any StorageClientProtocol { InMemoryStorageClient() }
}

extension DependencyValues {
    /// Клиент персистентного хранилища (чат, проекты).
    public var storageClient: any StorageClientProtocol {
        get { self[StorageClientKey.self] }
        set { self[StorageClientKey.self] = newValue }
    }
}

/// In-memory реализация `StorageClientProtocol` — для unit-тестов и preview.
/// Не пишет на диск, изолирована per-instance, потокобезопасна через `NSLock`.
public final class InMemoryStorageClient: StorageClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    public init() {}

    public func save<T: Codable>(_ value: T, forKey key: String) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw StorageError.encodingFailed(error)
        }
        lock.lock(); defer { lock.unlock() }
        store[key] = data
    }

    public func load<T: Codable>(forKey key: String) throws -> T? {
        lock.lock()
        let data = store[key]
        lock.unlock()
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw StorageError.decodingFailed(error)
        }
    }

    public func remove(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[key] = nil
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
    }
}
