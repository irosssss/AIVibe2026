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

        case resetToIdle
    }

    // MARK: - Dependencies

    @Dependency(\.aiAdvisorClient) var aiAdvisorClient

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
                return .none

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

                return .run { send in
                    do {
                        let advice = try await self.aiAdvisorClient.getAdvice(request)
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
                // Чат без приложенного фото: пользователь просто пишет вопрос.
                // На MVP-демо отвечаем мок-сообщением через дилей, чтобы
                // сработали thinking-индикаторы. После подключения backend
                // здесь будет вызов text-only endpoint AgentLoop.
                let input = state.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !input.isEmpty else { return .none }
                let userMsg = AdvisorChatMessage(text: input, provider: "", isUser: true)
                state.chatMessages.append(userMsg)
                state.currentInput = ""
                state.phase = .awaitingAI
                state.activeProvider = "Demo"
                return .run { send in
                    try? await Task.sleep(for: .seconds(1.5))
                    let reply = AdvisorChatMessage(
                        text: "Это демо-ответ. Прикрепите фото комнаты, чтобы получить настоящий совет от AI-дизайнера.",
                        provider: "Demo",
                        isUser: false
                    )
                    await send(.chatResponseReceived(reply))
                }

            case .chatResponseReceived(let msg):
                state.chatMessages.append(msg)
                state.phase = .result
                state.activeProvider = nil
                return .none

            case .binding:
                return .none

            case .resetToIdle:
                state = State()
                return .none
            }
        }
    }
}

// MARK: - AdvisorChatMessage

struct AdvisorChatMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let provider: String
    let isUser: Bool
    let timestamp: Date = Date()
}

// MARK: - Dependency Client

struct AIAdvisorClient: Sendable {
    var getAdvice: @Sendable (DesignRequest) async throws -> DesignAdvice
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

extension AIAdvisorClient: DependencyKey {
    static let liveValue = AIAdvisorClient(
        getAdvice: { request in
            let networkClient = NetworkClient()
            let prompt = request.buildYandexGPTPrompt()

            guard let url = URL(string: "https://your-function-url/ai-advisor") else {
                throw AIError.invalidResponse(provider: "backend", details: "Некорректный URL")
            }

            let body = AdvisorRequestBody(
                prompt: prompt,
                userId: "ios-device-id",
                imageBase64: request.imageAsBase64() ?? ""
            )
            let response: AdvisorResponseBody = try await networkClient.post(url: url, body: body)
            return DesignAdvice.parse(from: response.text, provider: response.provider)
        }
    )
}

extension DependencyValues {
    var aiAdvisorClient: AIAdvisorClient {
        get { self[AIAdvisorClient.self] }
        set { self[AIAdvisorClient.self] = newValue }
    }
}
