// AIAdvisorFeature.swift
// TCA Reducer — state machine переведённый из React useState hooks siegblink
// idle → capturing → processing → result → error

import ComposableArchitecture
import UIKit

// MARK: - Nested Types (вынесены из State для SwiftLint nesting rule)

enum AdvisorPhase: Equatable {
    case idle
    case capturing
    case processingImage
    case awaitingAI
    case result
    case error(String)
}

enum AdvisorImageSource: Equatable {
    case camera
    case gallery
    case roomScan
}

@Reducer
struct AIAdvisorFeature {

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        // Параметры дизайна
        var selectedStyle: DesignStyle = .modern
        var selectedRoomType: RoomType = .livingRoom
        var userComment: String = ""
        var promptStrength: Float = 0.7

        // Изображение
        var sourceImage: UIImage?
        var isShowingImagePicker: Bool = false
        var imageSource: AdvisorImageSource = .camera

        // Фаза обработки
        var phase: AdvisorPhase = .idle
        var activeProvider: String?

        // Результат
        var designAdvice: DesignAdvice?

        // Чат
        var chatMessages: [AdvisorChatMessage] = []
        var currentInput: String = ""

        // Живая подборка из партнёрского каталога под последний запрос (B4).
        // Пусто = показываем демо-стаб (PartnerCatalogStub).
        var suggestedProducts: [PartnerProduct] = []
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)

        case styleSelected(DesignStyle)
        case roomTypeSelected(RoomType)

        case imageSourceTapped(AdvisorImageSource)
        case imagePicked(UIImage)
        case imagePickerDismissed

        case analyzeButtonTapped
        case aiResponseReceived(DesignAdvice)
        case aiError(String)

        case sendChatMessage
        case sendTextOnlyMessage           // chat без вложенного фото
        case chatResponseReceived(AdvisorChatMessage)
        case catalogSuggestionsLoaded([PartnerProduct])

        case onAppear                              // загрузить сохранённый чат
        case chatHistoryLoaded([AdvisorChatMessage])

        case resetToIdle
    }

    // MARK: - Dependencies

    @Dependency(\.aiAdvisorClient) var aiAdvisorClient
    @Dependency(\.storageClient) var storageClient
    @Dependency(\.partnerCatalogClient) var partnerCatalogClient

    /// Ключ персистентного хранения истории чата (локально, B1).
    static let chatHistoryKey = "advisor_chat_history_v1"

    // MARK: - Reducer

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .styleSelected(let style):
                state.selectedStyle = style
                return .none

            case .roomTypeSelected(let type):
                state.selectedRoomType = type
                return .none

            case .imageSourceTapped(let source):
                state.imageSource = source
                state.isShowingImagePicker = true
                state.phase = .capturing
                return .none

            case .imagePicked(let image):
                state.sourceImage = image
                state.isShowingImagePicker = false
                state.phase = .idle
                return .none

            case .imagePickerDismissed:
                state.isShowingImagePicker = false
                state.phase = .idle
                return .none

            case .analyzeButtonTapped:
                guard let image = state.sourceImage else {
                    state.phase = .error("Выберите фото")
                    return .none
                }
                state.phase = .awaitingAI
                state.activeProvider = "YandexGPT"

                let request = DesignRequest(
                    roomType: state.selectedRoomType,
                    style: state.selectedStyle,
                    sourceImage: image,
                    userComment: state.userComment.isEmpty ? nil : state.userComment,
                    promptStrength: state.promptStrength
                )

                return .run { send in
                    do {
                        let advice = try await aiAdvisorClient.getAdvice(request)
                        await send(.aiResponseReceived(advice))
                    } catch {
                        await send(.aiError(error.localizedDescription))
                    }
                }

            case .aiResponseReceived(let advice):
                state.phase = .result
                state.designAdvice = advice
                state.activeProvider = nil
                // Добавляем в чат
                let msg = AdvisorChatMessage(
                    text: advice.concept,
                    provider: advice.provider,
                    isUser: false
                )
                state.chatMessages.append(msg)
                return persistChat(state.chatMessages)

            case .aiError(let message):
                state.phase = .error(message)
                state.activeProvider = nil
                return .none

            case .sendChatMessage:
                let input = state.currentInput.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !input.isEmpty else { return .none }

                // Defense in depth: если sourceImage отсутствует (например, standalone AI tab
                // без шага capture), молча падаем на text-only path вместо ошибки. Codex P1.
                guard let image = state.sourceImage else {
                    return .send(.sendTextOnlyMessage)
                }

                let userMsg = AdvisorChatMessage(text: input, provider: "", isUser: true)
                state.chatMessages.append(userMsg)
                state.currentInput = ""
                state.phase = .awaitingAI

                let request = DesignRequest(
                    roomType: state.selectedRoomType,
                    style: state.selectedStyle,
                    sourceImage: image,
                    userComment: input,
                    promptStrength: state.promptStrength
                )

                // Сохраняем сообщение пользователя ДО запроса (в том же эффекте),
                // чтобы оно не гонялось с записью полного транскрипта в
                // chatResponseReceived и не затирало ответ AI. Codex P2.
                return .run { [storageClient, aiAdvisorClient, messages = state.chatMessages] send in
                    try? storageClient.save(messages, forKey: Self.chatHistoryKey)
                    do {
                        let advice = try await aiAdvisorClient.getAdvice(request)
                        await send(.chatResponseReceived(
                            AdvisorChatMessage(
                                text: advice.concept,
                                provider: advice.provider,
                                isUser: false
                            )
                        ))
                    } catch {
                        await send(.aiError(error.localizedDescription))
                    }
                }

            case .sendTextOnlyMessage:
                // Чат без приложенного фото: вопрос уходит на наш бэкенд
                // (ai-advisor: promptGuard → RAG → роутер Lite/Pro → Triplex).
                // Бэкенд недоступен/не сконфигурирован → офлайн-фолбэк,
                // чат не падает. Параллельно — живая подборка каталога (B4).
                let input = state.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !input.isEmpty else { return .none }
                let userMsg = AdvisorChatMessage(text: input, provider: "", isUser: true)
                state.chatMessages.append(userMsg)
                state.currentInput = ""
                state.phase = .awaitingAI
                state.activeProvider = nil
                // Сохраняем сообщение пользователя ДО ответа (в том же эффекте) —
                // последовательно, без гонки с записью полного транскрипта. Codex P2.
                return .run { [storageClient, aiAdvisorClient, partnerCatalogClient, messages = state.chatMessages] send in
                    try? storageClient.save(messages, forKey: Self.chatHistoryKey)

                    // Подборка каталога — параллельно с ответом AI, best-effort.
                    async let suggestions = (try? partnerCatalogClient.search(input, nil, nil)) ?? []

                    do {
                        let reply = try await aiAdvisorClient.getChatReply(input)
                        await send(.chatResponseReceived(reply))
                    } catch {
                        let fallback = AdvisorChatMessage(
                            text: "Сейчас нет связи с AI-сервером — проверьте интернет и попробуйте ещё раз. "
                                + "А пока могу показать подборку из каталога фабрик ниже.",
                            provider: "offline",
                            isUser: false
                        )
                        await send(.chatResponseReceived(fallback))
                    }
                    await send(.catalogSuggestionsLoaded(suggestions))
                }

            case let .catalogSuggestionsLoaded(products):
                // Пустой результат не затирает прежнюю подборку (UI сам
                // деградирует в демо-стаб, если подборок ещё не было).
                if !products.isEmpty {
                    state.suggestedProducts = products
                }
                return .none

            case .chatResponseReceived(let msg):
                state.chatMessages.append(msg)
                state.phase = .result
                state.activeProvider = nil
                return persistChat(state.chatMessages)

            case .onAppear:
                // Подгружаем сохранённую историю чата при первом показе экрана.
                return .run { [storageClient] send in
                    if let saved: [AdvisorChatMessage] = try? storageClient.load(forKey: Self.chatHistoryKey) {
                        await send(.chatHistoryLoaded(saved))
                    }
                }

            case .chatHistoryLoaded(let messages):
                // Не затираем уже накопленные в этой сессии сообщения.
                if state.chatMessages.isEmpty {
                    state.chatMessages = messages
                }
                return .none

            case .binding:
                return .none

            case .resetToIdle:
                state = State()
                return .run { [storageClient] _ in
                    try? storageClient.remove(forKey: Self.chatHistoryKey)
                }
            }
        }
    }

    /// Сохраняет историю чата в локальное хранилище (best-effort, ошибки не фатальны).
    private func persistChat(_ messages: [AdvisorChatMessage]) -> Effect<Action> {
        .run { [storageClient] _ in
            try? storageClient.save(messages, forKey: Self.chatHistoryKey)
        }
    }
}

// MARK: - AdvisorChatMessage

struct AdvisorChatMessage: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let text: String
    let provider: String
    let isUser: Bool
    let timestamp: Date

    // Дефолты держим в init, а не inline: при inline `let id = UUID()`
    // синтезированный Codable не декодирует id (генерит новый) — ломает round-trip.
    init(id: UUID = UUID(), text: String, provider: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.provider = provider
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - Dependency Client

struct AIAdvisorClient: Sendable {
    var getAdvice: @Sendable (DesignRequest) async throws -> DesignAdvice
    /// Текстовый чат без фото: вопрос → живой ответ ai-advisor.
    var getChatReply: @Sendable (String) async throws -> AdvisorChatMessage
}

// MARK: - Dependency Registration

private struct AdvisorRequestBody: Encodable {
    let prompt: String
    let userId: String
    let imageBase64: String
}

private struct AdvisorResponseBody: Decodable {
    let text: String
    let provider: String
}

/// POST на ai-advisor (контракт backend/functions/ai-advisor/index.js).
/// URL/токен — из BackendConfig (Info.plist → BackendConfig.plist);
/// не сконфигурировано → ошибка без похода в сеть (graceful fail, L5/#22).
private func postToAdvisor(prompt: String, imageBase64: String) async throws -> AdvisorResponseBody {
    guard let url = BackendConfig.aiAdvisorURL else {
        throw AIError.invalidResponse(provider: "backend", details: "URL ai-advisor не сконфигурирован")
    }
    let body = AdvisorRequestBody(
        prompt: prompt,
        // L4 (#22): реальный анонимный per-install id вместо 'ios-device-id',
        // иначе все юзеры делят один rate-limit-бакет (#17).
        userId: AnonymousUserID.current,
        imageBase64: imageBase64
    )
    // X-App-Token закрывает unauthenticated abuse (#20/#14).
    return try await NetworkClient(timeout: 40).post(
        url: url, body: body, headers: BackendConfig.authHeaders
    )
}

extension AIAdvisorClient: DependencyKey {
    static let liveValue = AIAdvisorClient(
        getAdvice: { request in
            let prompt = request.buildYandexGPTPrompt()
            let response = try await postToAdvisor(
                prompt: prompt,
                imageBase64: request.imageAsBase64() ?? ""
            )
            return DesignAdvice.parse(from: response.text, provider: response.provider)
        },
        getChatReply: { question in
            // Лёгкая роль-преамбула: ответ по теме приложения, без JSON-схем.
            let prompt = """
            Ты — ассистент по дизайну интерьеров в приложении AIVibe. \
            Отвечай по-русски, кратко и практично (3–6 предложений), \
            с конкретными советами по мебели и планировке.

            Вопрос пользователя: \(question)
            """
            let response = try await postToAdvisor(prompt: prompt, imageBase64: "")
            return AdvisorChatMessage(
                text: response.text,
                provider: response.provider,
                isUser: false
            )
        }
    )
}

extension DependencyValues {
    var aiAdvisorClient: AIAdvisorClient {
        get { self[AIAdvisorClient.self] }
        set { self[AIAdvisorClient.self] = newValue }
    }
}
