// AIVibeTests/Storage/StorageClientTests.swift
// B1: персистентность — round-trip хранилища + Codable-контракт DTO.

import XCTest
@testable import AIVibe

final class StorageClientTests: XCTestCase {

    private struct Sample: Codable, Equatable {
        let a: Int
        let b: String
    }

    /// Файловый клиент в изолированной temp-директории (не трогаем Caches приложения).
    private func makeTempClient() -> StorageClient {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIVibeTest-\(UUID().uuidString)")
        return StorageClient(storageDirectory: dir)
    }

    // MARK: - File-based StorageClient

    func testSaveLoadRoundTrip() throws {
        let client = makeTempClient()
        let value = Sample(a: 42, b: "привет")
        try client.save(value, forKey: "k")
        let loaded: Sample? = try client.load(forKey: "k")
        XCTAssertEqual(loaded, value)
    }

    func testLoadMissingReturnsNil() throws {
        let client = makeTempClient()
        let loaded: Sample? = try client.load(forKey: "absent")
        XCTAssertNil(loaded)
    }

    func testRemove() throws {
        let client = makeTempClient()
        try client.save(Sample(a: 1, b: "x"), forKey: "k")
        try client.remove(forKey: "k")
        let loaded: Sample? = try client.load(forKey: "k")
        XCTAssertNil(loaded)
    }

    func testClear() throws {
        let client = makeTempClient()
        try client.save(Sample(a: 1, b: "x"), forKey: "k1")
        try client.save(Sample(a: 2, b: "y"), forKey: "k2")
        try client.clear()
        let l1: Sample? = try client.load(forKey: "k1")
        let l2: Sample? = try client.load(forKey: "k2")
        XCTAssertNil(l1)
        XCTAssertNil(l2)
    }

    // MARK: - InMemory клиент (для тестов/preview)

    func testInMemoryRoundTrip() throws {
        let client = InMemoryStorageClient()
        try client.save(Sample(a: 7, b: "z"), forKey: "k")
        let loaded: Sample? = try client.load(forKey: "k")
        XCTAssertEqual(loaded, Sample(a: 7, b: "z"))
    }

    // MARK: - Codable-контракт персистентных DTO

    func testChatMessageCodableRoundTrip() throws {
        let client = InMemoryStorageClient()
        let msgs = [
            AdvisorChatMessage(text: "вопрос", provider: "", isUser: true),
            AdvisorChatMessage(text: "ответ", provider: "yandexgpt", isUser: false)
        ]
        try client.save(msgs, forKey: "chat")
        let loaded: [AdvisorChatMessage]? = try client.load(forKey: "chat")
        XCTAssertEqual(loaded, msgs)
    }

    func testHomeProjectCodableRoundTrip() throws {
        let client = InMemoryStorageClient()
        let projects = HomeFeature.mockProjects
        try client.save(projects, forKey: "projects")
        let loaded: [HomeProject]? = try client.load(forKey: "projects")
        XCTAssertEqual(loaded, projects)
    }
}
