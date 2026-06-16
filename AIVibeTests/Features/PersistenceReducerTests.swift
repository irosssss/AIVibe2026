// AIVibeTests/Features/PersistenceReducerTests.swift
// B1: проверка, что редьюсеры загружают сохранённое состояние при .onAppear.

import ComposableArchitecture
import XCTest
@testable import AIVibe

@MainActor
final class PersistenceReducerTests: XCTestCase {

    /// AIAdvisor: при .onAppear подгружается ранее сохранённая история чата.
    func testAdvisorOnAppearLoadsPersistedChat() async {
        let storage = InMemoryStorageClient()
        let saved = [
            AdvisorChatMessage(text: "старый вопрос", provider: "", isUser: true),
            AdvisorChatMessage(text: "старый ответ", provider: "yandexgpt", isUser: false)
        ]
        try? storage.save(saved, forKey: AIAdvisorFeature.chatHistoryKey)

        let store = TestStore(initialState: AIAdvisorFeature.State()) {
            AIAdvisorFeature()
        } withDependencies: {
            $0.storageClient = storage
        }

        await store.send(.onAppear)
        await store.receive(\.chatHistoryLoaded) {
            $0.chatMessages = saved
        }
    }

    /// Home: при .onAppear подгружаются ранее сохранённые проекты.
    func testHomeOnAppearLoadsPersistedProjects() async {
        let storage = InMemoryStorageClient()
        let saved = [
            HomeProject(name: "Ванная", tone: "sand", step: 2, totalSteps: 5,
                        currentBudget: 30_000, maxBudget: 90_000)
        ]
        try? storage.save(saved, forKey: HomeFeature.projectsKey)

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.storageClient = storage
        }

        await store.send(.onAppear)
        await store.receive(\.projectsLoaded) {
            $0.projects = saved
        }
    }

    /// Home: на первом запуске (пусто) текущий набор проектов сохраняется как seed.
    /// Живой дефолт State пуст (без фейковых проектов), поэтому стартовый набор
    /// задаём явно — проверяем сам механизм seed.
    func testHomeOnAppearSeedsWhenEmpty() async {
        let storage = InMemoryStorageClient()

        let store = TestStore(initialState: HomeFeature.State(projects: HomeFeature.mockProjects)) {
            HomeFeature()
        } withDependencies: {
            $0.storageClient = storage
        }

        await store.send(.onAppear)
        // Нет projectsLoaded — состояние не меняется, но seed записан в хранилище.
        await store.finish()
        let seeded: [HomeProject]? = try? storage.load(forKey: HomeFeature.projectsKey)
        XCTAssertEqual(seeded, HomeFeature.mockProjects)
    }

    /// Home: новый пользователь (пустой живой State) НЕ получает фейковых проектов в хранилище.
    func testHomeOnAppearDoesNotSeedFakeProjects() async {
        let storage = InMemoryStorageClient()

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.storageClient = storage
        }

        await store.send(.onAppear)
        await store.finish()
        let seeded: [HomeProject]? = try? storage.load(forKey: HomeFeature.projectsKey)
        XCTAssertEqual(seeded, [])
    }
}
