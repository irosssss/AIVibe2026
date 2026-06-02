// AIVibe/Features/AIAdvisor/AIAdvisorChatView.swift
// Экран AI-чата: welcome / active / fallback.
// Дизайн: docs/design/ai-vibe/project/chat.jsx
//
// Reducer (AIAdvisorFeature) меняем по минимуму, чтобы не задевать смежные модули.
// UI-only состояния (suggestions, pendingApproval, fallbackBanner) держим локально.

import ComposableArchitecture
import SwiftUI

struct AIAdvisorChatView: View {

    @Bindable var store: StoreOf<AIAdvisorFeature>

    /// Sticky-бар бюджета над composer — отображается, если значение задано.
    let budget: BudgetSnapshot?

    /// Pending approval-карточка (модальный кусок поверх потока).
    @State private var pendingApproval: PendingApproval?

    /// Inline-карточки мебели (демо-данные; в проде придут из MarketplaceClient).
    @State private var inlineFurniture: [ChatFurnitureItem] = []

    /// Активные tool-вызовы AI (показываются пока `isThinking`).
    /// В проде — обновляются из AgentLoop.run events.
    @State private var toolCalls: [ToolCallIndicator] = []

    /// ID последнего AI-сообщения, которое сейчас «стримится» (посимвольно).
    @State private var streamingMessageId: UUID?
    /// Накопленный текст текущего стриминга.
    @State private var streamingText: String = ""

    /// Колбэк наружу — тап по карточке мебели в inline-карусели.
    let onProductTap: (ChatFurnitureItem) -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    init(
        store: StoreOf<AIAdvisorFeature>,
        budget: BudgetSnapshot? = nil,
        onProductTap: @escaping (ChatFurnitureItem) -> Void = { _ in }
    ) {
        self.store = store
        self.budget = budget
        self.onProductTap = onProductTap
    }

    public var body: some View {
        AIThemeReader {
            ZStack {
                c.bg.ignoresSafeArea()

                if store.chatMessages.isEmpty && store.phase == .idle {
                    welcomeContent
                } else {
                    activeContent
                }

                VStack {
                    ChatTopBar(skill: currentSkill, thinking: isThinking)
                    Spacer()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(
                    text: $store.currentInput,
                    onSend: { sendMessage() },
                    onAttach: { /* placeholder */ },
                    budget: budget
                )
            }
            .task {
                // Загружаем сохранённую историю чата при открытии экрана (B1).
                store.send(.onAppear)
            }
            .onChange(of: store.chatMessages.count) { _, count in
                startStreamingIfNeeded(count: count)
            }
            .onChange(of: store.phase) { _, newPhase in
                // Демо-индикаторы tool-вызовов на время «AI думает».
                // В проде заменится на events из AgentLoop.run.
                switch newPhase {
                case .awaitingAI, .processingImage:
                    toolCalls = [
                        .init(kind: .analyzingRoom, detail: "Гостиная 18 м²"),
                        .init(kind: .searching, detail: "Ozon · WB"),
                        .init(kind: .matchingFurniture, detail: "до 50 000 ₽")
                    ]
                default:
                    toolCalls = []
                }
            }
        }
    }

    // MARK: - Dispatch

    /// Запускает стриминг для последнего AI-сообщения, если оно новое.
    private func startStreamingIfNeeded(count: Int) {
        guard count > 0 else { return }
        let last = store.chatMessages[count - 1]
        guard !last.isUser else { return }
        streamingMessageId = last.id
        streamingText = ""
        streamText(last.text, messageId: last.id)
    }

    /// Посимвольное (по 3 символа / 30 мс) раскрытие текста AI-ответа.
    private func streamText(_ fullText: String, messageId: UUID) {
        var chunks: [String] = []
        var idx = fullText.startIndex
        while idx < fullText.endIndex {
            let end = fullText.index(
                idx, offsetBy: 3,
                limitedBy: fullText.endIndex
            ) ?? fullText.endIndex
            chunks.append(String(fullText[idx..<end]))
            idx = end
        }
        Task { @MainActor in
            for chunk in chunks {
                guard streamingMessageId == messageId else { return }
                try? await Task.sleep(nanoseconds: 30_000_000)
                streamingText += chunk
            }
            if streamingMessageId == messageId {
                streamingMessageId = nil
            }
        }
    }

    /// Маршрутизирует send в нужный action reducer'а.
    /// Если у пользователя приложено фото — идём в полный image-pipeline
    /// (`.sendChatMessage`). Иначе — text-only path (demo mock).
    private func sendMessage() {
        if store.sourceImage != nil {
            store.send(.sendChatMessage)
        } else {
            store.send(.sendTextOnlyMessage)
        }
    }

    // MARK: - State derivations

    private var currentSkill: String {
        if store.activeProvider != nil { return "budget_optimizer" }
        return store.chatMessages.isEmpty ? "design_advisor" : "furniture_matcher"
    }

    private var isThinking: Bool {
        store.phase == .awaitingAI || store.phase == .processingImage
    }

    private var fallbackBanner: String? {
        // Если активен провайдер и это не основной — считаем что fallback.
        if let provider = store.activeProvider, provider != "YandexGPT" {
            return provider
        }
        return nil
    }

    // MARK: - Welcome (state 1)

    private var welcomeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [c.sandSoft, c.terracottaSoft],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(c.terracotta)
                }
                .frame(width: 64, height: 64)
                .padding(.bottom, 16)

                Text("Помогу с дизайном")
                    .aiType(.title1)
                    .foregroundStyle(c.onSurface)

                Text("Опишите задачу или выберите подсказку. Я предложу варианты с реальными ценами на Ozon и Wildberries.")
                    .aiType(.body)
                    .foregroundStyle(c.onSurfaceMuted)
                    .padding(.top, 6)

                CapsLabel("Примеры вопросов")
                    .padding(.top, 28)
                    .padding(.bottom, 10)

                VStack(spacing: 8) {
                    ForEach(Self.suggestions) { sug in
                        SuggestionRow(suggestion: sug) {
                            Haptics.selection()
                            store.currentInput = sug.text
                            sendMessage()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 110)   // под top bar
            .padding(.bottom, 32)
        }
    }

    // MARK: - Active (state 2 + 3)

    private var activeContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let provider = fallbackBanner {
                        FallbackBanner(provider: provider)
                            .padding(.horizontal, 16)
                    }

                    ForEach(store.chatMessages) { msg in
                        if msg.isUser {
                            UserBubble(text: msg.text)
                        } else {
                            AIBubble(
                                text: msg.id == streamingMessageId ? streamingText : msg.text,
                                provider: msg.provider.isEmpty ? nil : msg.provider,
                                streaming: msg.id == streamingMessageId
                            )
                        }
                    }

                    // Слайдер «до/после» — показывается, если AI вернул результат
                    // для загруженного фото комнаты.
                    if store.designAdvice != nil && store.sourceImage != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel("До / После")
                                .padding(.horizontal, 16)
                            BeforeAfterSlider(beforeTone: .sand, afterTone: .sage)
                                .padding(.horizontal, 16)
                        }
                    }

                    if !inlineFurniture.isEmpty {
                        InlineFurnitureRow(items: inlineFurniture) { item in
                            onProductTap(item)
                        }
                    }

                    // Тут отображаются tool-вызовы агента — пока mock
                    // (показывается, если AI «думает»).
                    if isThinking && !toolCalls.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(toolCalls) { call in
                                ToolCallRow(call: call)
                            }
                        }
                    }

                    if let approval = pendingApproval {
                        ApprovalCard(
                            approval: approval,
                            onConfirm: { pendingApproval = nil },
                            onCancel: { pendingApproval = nil }
                        )
                    }

                    Color.clear.frame(height: 12).id("bottom")
                }
                .padding(.top, 130)   // под top bar (54 status + ~76 chrome)
                .padding(.bottom, budget == nil ? 16 : 80)
            }
            .onChange(of: store.chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Mock helpers (для дизайн-демонстрации)

    private static let suggestions: [ChatSuggestion] = [
        .init(icon: "sparkles", text: "Как выбрать стиль для гостиной?"),
        .init(icon: "cube", text: "Что делать с маленькой кухней 8 м²?"),
        .init(icon: "bag", text: "Подбери диван до 50 000 ₽"),
        .init(icon: "ruler", text: "Какая высота столешницы оптимальна?")
    ]
}

// MARK: - DTOs (внешние, чтобы вью был параметризируем)

public struct BudgetSnapshot: Equatable, Sendable {
    public let current: Int
    public let max: Int
    public init(current: Int, max: Int) {
        self.current = current
        self.max = max
    }
    public var ratio: Double {
        guard max > 0 else { return 0 }
        return Double(current) / Double(max)
    }
}

public struct PendingApproval: Equatable, Sendable {
    public let title: String
    public let detail: String
    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public struct ChatFurnitureItem: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let price: Int
    public let tone: AIPhotoTone
    public let market: AIMarket

    public init(title: String, price: Int, tone: AIPhotoTone, market: AIMarket) {
        self.title = title
        self.price = price
        self.tone = tone
        self.market = market
    }
}

struct ChatSuggestion: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
}
