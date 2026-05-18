// AIAdvisorFeature.swift
// TCA Reducer — state machine переведённый из React useState hooks siegblink
// idle → capturing → processing → result → error

import ComposableArchitecture
import UIKit

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
        var imageSource: ImageSource = .camera

        // Фаза обработки
        var phase: Phase = .idle
        var activeProvider: String?

        // Результат
        var designAdvice: DesignAdvice?

        // Чат
        var chatMessages: [ChatMessage] = []
        var currentInput: String = ""

        enum Phase: Equatable {
            case idle
            case capturing
            case processingImage
            case awaitingAI
            case result
            case error(String)
        }

        enum ImageSource: Equatable {
            case camera
            case gallery
            case roomScan
        }
    }

    // MARK: - Action

    enum Action: BindableAction {
        case binding(BindingAction<State>)

        case styleSelected(DesignStyle)
        case roomTypeSelected(RoomType)

        case imageSourceTapped(State.ImageSource)
        case imagePicked(UIImage)
        case imagePickerDismissed

        case analyzeButtonTapped
        case aiResponseReceived(DesignAdvice)
        case aiError(String)

        case sendChatMessage
        case chatResponseReceived(ChatMessage)

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
                guard state.sourceImage != nil else {
                    state.phase = .error("Выберите фото")
                    return .none
                }
                state.phase = .awaitingAI
                state.activeProvider = "YandexGPT"

                let request = DesignRequest(
                    roomType: state.selectedRoomType,
                    style: state.selectedStyle,
                    sourceImage: state.sourceImage!,
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
                let msg = ChatMessage(
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

                let userMsg = ChatMessage(text: input, provider: "", isUser: true)
                state.chatMessages.append(userMsg)
                state.currentInput = ""
                state.phase = .awaitingAI

                guard let image = state.sourceImage else {
                    state.phase = .error("Нет изображения")
                    return .none
                }

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
                            ChatMessage(
                                text: advice.concept,
                                provider: advice.provider,
                                isUser: false
                            )
                        ))
                    } catch {
                        await send(.aiError(error.localizedDescription))
                    }
                }

            case .chatResponseReceived(let msg):
                state.chatMessages.append(msg)
                state.phase = .result
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

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable, Sendable {
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

extension AIAdvisorClient: DependencyKey {
    static let liveValue = AIAdvisorClient(
        getAdvice: { request in
            // Вызов backend /ai-advisor через NetworkClient
            let networkClient = NetworkClient(baseURL: "https://your-function-url")
            let prompt = request.buildYandexGPTPrompt()
            let body: [String: Any] = [
                "prompt": prompt,
                "userId": "ios-device-id",
                "imageBase64": request.imageAsBase64() ?? ""
            ]
            let response: [String: Any] = try await networkClient.post(
                "/ai-advisor",
                body: body
            )
            guard let text = response["text"] as? String,
                  let provider = response["provider"] as? String else {
                throw AIError.invalidResponse
            }
            return DesignAdvice.parse(from: text, provider: provider)
        }
    )
}

extension DependencyValues {
    var aiAdvisorClient: AIAdvisorClient {
        get { self[AIAdvisorClient.self] }
        set { self[AIAdvisorClient.self] = newValue }
    }
}