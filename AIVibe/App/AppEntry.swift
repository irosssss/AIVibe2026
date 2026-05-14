// AIVibe/App/AppEntry.swift
// Модуль: App
// Точка входа приложения. Инициализирует TCA-зависимости с live-провайдерами.
// Вызывается один раз при старте. Все DI-ключи регистрируются через withDependencies.

import SwiftUI
import ComposableArchitecture

@main
struct AIVibeApp: App {
    @State private var router: AIProviderRouter?

    init() {
        // Инициализируем зависимости до построения Scene
    }

    var body: some Scene {
        WindowGroup {
            // Оборачиваем всё дерево в withDependencies, чтобы TCA-редьюсеры
            // получали реальный AIProviderRouter с Triplex Fallback
            if let router {
                AppRootView()
                    .task {
                        // Фоновый health-check стартует автоматически в роутере
                    }
            } else {
                ProgressView("Загрузка AI-модулей…")
                    .task {
                        self.router = AppDependencies.prepareLiveRouter()
                    }
            }
        }
    }
}

// MARK: - Корневой экран (заглушка для SESSION_02)

/// Временный корневой экран. В SESSION_03 будет заменён на ARDesigner.
private struct AppRootView: View {
    @Dependency(\.aiRouter) private var router

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("AIVibe")
                .font(.largeTitle)
                .bold()

            Text("AI-дизайнер интерьеров")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Проверить AI-роутер") {
                Task {
                    await testRouter()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func testRouter() async {
        let prompt = AIPrompt(
            messages: [ChatMessage(role: .user, content: "Какой стиль интерьера подойдёт для маленькой кухни?")]
        )

        do {
            let response = try await router.complete(prompt: prompt)
            print("✅ AI ответил: \(response.text.prefix(100))... (провайдер: \(response.providerName))")
        } catch {
            print("❌ Ошибка AI: \(error.localizedDescription)")
        }
    }
}
