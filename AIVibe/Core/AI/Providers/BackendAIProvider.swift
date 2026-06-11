// AIVibe/Core/AI/Providers/BackendAIProvider.swift
// Модуль: Core/AI
// Провайдер «через наш бэкенд»: ходит в Cloud Function ai-advisor
// (X-App-Token), где уже есть promptGuard, rate limit, RAG-обогащение,
// роутер Lite/Pro (B7) и Triplex Fallback YandexGPT→GigaChat.
//
// Зачем: в iOS-бандле НЕТ ключей AI-провайдеров (требование CLAUDE.md),
// поэтому прямые YandexGPT/GigaChat-провайдеры на устройстве недоступны.
// Этот провайдер ставится ПЕРВЫМ в AIProviderRouter — телефон получает
// живой AI без секретов в бандле. Прямые провайдеры остаются для
// окружений с env-ключами (CI-интеграция, отладка).

import Foundation

public struct BackendAIProvider: AIProviderProtocol {

    public let name = "Backend"

    /// Лимит бэкенда (promptGuard MAX_PROMPT_LENGTH = 4000) с запасом.
    private static let maxPromptLength = 3900

    private let networkClient: NetworkClient

    public init() {
        // Дизайн-генерация (LLM считает расстановку) может занимать до ~25 с
        // на стороне функции (timeoutMs=25000) — даём сетевой запас.
        self.networkClient = NetworkClient(timeout: 40)
    }

    public var isAvailable: Bool {
        get async { BackendConfig.isConfigured }
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        try await send(prompt: Self.flatten(prompt), imageBase64: nil)
    }

    public func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse {
        try await send(prompt: prompt, imageBase64: imageData.base64EncodedString())
    }

    // MARK: - Запрос

    private struct RequestBody: Encodable {
        let prompt: String
        let userId: String
        let imageBase64: String?
    }

    private struct ResponseBody: Decodable {
        let text: String
        let provider: String
        let model: String?
    }

    private func send(prompt: String, imageBase64: String?) async throws -> AIResponse {
        guard let url = BackendConfig.aiAdvisorURL, BackendConfig.appToken != nil else {
            throw AIError.providerUnavailable(provider: name)
        }

        let body = RequestBody(
            prompt: String(prompt.prefix(Self.maxPromptLength)),
            userId: AnonymousUserID.current,
            imageBase64: imageBase64
        )

        let response: ResponseBody = try await networkClient.post(
            url: url,
            body: body,
            headers: BackendConfig.authHeaders
        )

        return AIResponse(
            text: response.text,
            providerName: "Backend/\(response.provider)"
        )
    }

    /// Сообщения промпта → один текст для контракта бэкенда ({prompt}).
    /// Роли сохраняются разделителями: system-инструкция идёт первой.
    private static func flatten(_ prompt: AIPrompt) -> String {
        prompt.messages
            .map { $0.content }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
