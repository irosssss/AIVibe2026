# СЕССИЯ 5 — AIAdvisor Feature (по мотивам siegblink/interior-designer-ai)

> Добавь в контекст: @PROJECT_RULES.md @Core/AI/AIProviderRouter.swift @Core/AI/AIModels.swift
> Режим: Agent

---

## Что изучили в siegblink/interior-designer-ai

Репо использует модель `adirik/interior-design` через Replicate API (2 млн запросов).
API-контракт этой модели:

```
Вход:
  image          — фото комнаты (URL или base64)
  prompt         — текстовое описание желаемого стиля
  negative_prompt — чего избегать
  prompt_strength — сила трансформации (0.0–1.0)
  guidance_scale  — следование промпту
  seed            — для воспроизводимости

Выход:
  output_image   — URL переработанного изображения
```

**Ключевые паттерны которые берём:**
1. Промпт = `{стиль} {тип_комнаты}, {детали}` — строим через enum-комбинацию
2. Состояния: `idle → capturing → processing → result → error`
3. Before/After сравнение — слайдер поверх изображений
4. Style picker + Room type picker — горизонтальный скролл
5. Negative prompt — всегда фиксированный для качества

**Что НЕ берём (заменяем на наш стек):**
- Replicate API → YandexGPT 5 (vision mode) + GigaChat (multimodal)
- Next.js компоненты → SwiftUI + TCA
- Загрузка файла → UIImagePickerController / Camera / RoomScan результат

---

## Архитектура AIAdvisor Feature (TCA)

### Файловая структура

```
Features/AIAdvisor/
├── AIAdvisorFeature.swift      — Reducer + State + Action
├── AIAdvisorView.swift         — SwiftUI root view
├── Views/
│   ├── PhotoInputView.swift    — камера / галерея / из RoomScan
│   ├── StylePickerView.swift   — выбор стиля (горизонтальный скролл)
│   ├── RoomTypePickerView.swift — тип комнаты
│   ├── ChatBubbleView.swift    — сообщение AI
│   ├── BeforeAfterSliderView.swift — сравнение до/после
│   └── DesignResultView.swift  — результат + кнопки
└── Models/
    ├── DesignStyle.swift       — enum стилей
    ├── RoomType.swift          — enum типов комнат
    └── DesignRequest.swift     — структура запроса
```

---

## 1. Модели данных

### Файл: `Features/AIAdvisor/Models/DesignStyle.swift`

```swift
// DesignStyle.swift
// Порт паттерна из siegblink: Modern/Vintage/Minimalist/Professional
// Расширен российскими стилями

import Foundation

enum DesignStyle: String, CaseIterable, Codable, Sendable {
    // Из siegblink
    case modern       = "modern"
    case vintage      = "vintage"
    case minimalist   = "minimalist"
    case professional = "professional"
    // Добавлено для РФ-рынка
    case scandinavian = "scandinavian"
    case classicRussian = "classic_russian"
    case loft         = "loft"
    case eclectic     = "eclectic"

    var displayName: String {
        switch self {
        case .modern:         return "Современный"
        case .vintage:        return "Винтаж"
        case .minimalist:     return "Минимализм"
        case .professional:   return "Деловой"
        case .scandinavian:   return "Скандинавский"
        case .classicRussian: return "Классика"
        case .loft:           return "Лофт"
        case .eclectic:       return "Эклектика"
        }
    }

    var emoji: String {
        switch self {
        case .modern:         return "🏙"
        case .vintage:        return "🕰"
        case .minimalist:     return "◻️"
        case .professional:   return "💼"
        case .scandinavian:   return "🌿"
        case .classicRussian: return "🏛"
        case .loft:           return "🏭"
        case .eclectic:       return "🎨"
        }
    }

    // Ключевая функция — промпт-инжиниринг для YandexGPT
    // Переведённый паттерн из siegblink: prompt = style + room + details
    var promptModifier: String {
        switch self {
        case .modern:
            return "современный стиль, чистые линии, нейтральные цвета, минимум декора"
        case .vintage:
            return "винтажный стиль, тёплые тона, состаренная мебель, ретро-детали"
        case .minimalist:
            return "минималистичный стиль, много света, только необходимое, белый и серый"
        case .professional:
            return "деловой стиль, строгость, тёмные акценты, представительность"
        case .scandinavian:
            return "скандинавский стиль, натуральное дерево, белый, уют, функциональность"
        case .classicRussian:
            return "классический стиль, симметрия, лепнина, богатые материалы, традиционность"
        case .loft:
            return "лофт-стиль, кирпич, металл, открытые коммуникации, индустриальный шик"
        case .eclectic:
            return "эклектика, смешение стилей, яркие акценты, авторский подход"
        }
    }

    // Negative prompt — заимствован из adirik/interior-design модели
    var negativePrompt: String {
        "низкое качество, размытость, деформации, людей в кадре, " +
        "неправдоподобная геометрия, нереалистичное освещение"
    }
}
```

### Файл: `Features/AIAdvisor/Models/RoomType.swift`

```swift
// RoomType.swift
// Из siegblink: Living Room / Dining Room / Bedroom / Bathroom / Office

import Foundation

enum RoomType: String, CaseIterable, Codable, Sendable {
    case livingRoom  = "living_room"
    case bedroom     = "bedroom"
    case kitchen     = "kitchen"
    case bathroom    = "bathroom"
    case office      = "office"
    case diningRoom  = "dining_room"
    case hallway     = "hallway"
    case childRoom   = "child_room"

    var displayName: String {
        switch self {
        case .livingRoom:  return "Гостиная"
        case .bedroom:     return "Спальня"
        case .kitchen:     return "Кухня"
        case .bathroom:    return "Ванная"
        case .office:      return "Кабинет"
        case .diningRoom:  return "Столовая"
        case .hallway:     return "Прихожая"
        case .childRoom:   return "Детская"
        }
    }

    var emoji: String {
        switch self {
        case .livingRoom:  return "🛋"
        case .bedroom:     return "🛏"
        case .kitchen:     return "🍳"
        case .bathroom:    return "🚿"
        case .office:      return "💻"
        case .diningRoom:  return "🍽"
        case .hallway:     return "🚪"
        case .childRoom:   return "🧸"
        }
    }

    var promptContext: String {
        switch self {
        case .livingRoom:  return "жилая комната (гостиная)"
        case .bedroom:     return "спальня"
        case .kitchen:     return "кухня"
        case .bathroom:    return "ванная комната"
        case .office:      return "домашний кабинет"
        case .diningRoom:  return "столовая"
        case .hallway:     return "прихожая"
        case .childRoom:   return "детская комната"
        }
    }
}
```

### Файл: `Features/AIAdvisor/Models/DesignRequest.swift`

```swift
// DesignRequest.swift
// Аналог API-запроса к adirik/interior-design, адаптирован для YandexGPT

import UIKit
import Foundation

struct DesignRequest: Sendable {
    let roomType: RoomType
    let style: DesignStyle
    let sourceImage: UIImage          // фото из камеры / галереи / RoomScan
    let userComment: String?          // дополнительное пожелание пользователя
    let promptStrength: Float         // 0.0–1.0 (как в adirik модели)

    // КЛЮЧЕВОЙ ПАТТЕРН из siegblink:
    // prompt = style_modifier + room_context + details
    // Переведено на YandexGPT format
    func buildYandexGPTPrompt() -> String {
        var parts: [String] = []

        parts.append("Ты профессиональный дизайнер интерьеров.")
        parts.append("Проанализируй фотографию \(roomType.promptContext) и предложи детальное описание редизайна.")
        parts.append("Стиль: \(style.promptModifier).")

        if let comment = userComment, !comment.isEmpty {
            parts.append("Дополнительное пожелание: \(comment).")
        }

        parts.append("""
        Ответ должен содержать:
        1. Описание концепции (2–3 предложения)
        2. Рекомендации по цветовой палитре (3–5 цветов с названиями)
        3. Рекомендации по мебели (5–7 позиций с конкретными названиями)
        4. Советы по освещению (2–3 рекомендации)
        5. Декор и аксессуары (3–5 позиций)
        6. Ориентировочный бюджет (эконом / средний / премиум)
        Ответ на русском языке.
        """)

        return parts.joined(separator: "\n")
    }

    // Для imageBase64 → backend
    func imageAsBase64() -> String? {
        sourceImage
            .jpegData(compressionQuality: 0.85)?
            .base64EncodedString()
    }
}
```

---

## 2. TCA Reducer

### Файл: `Features/AIAdvisor/AIAdvisorFeature.swift`

```swift
// AIAdvisorFeature.swift
// TCA Reducer — state machine переведённый из React useState hooks siegblink
// idle → capturing → processing → result → error

import ComposableArchitecture
import UIKit

@Reducer
struct AIAdvisorFeature {

    // MARK: — State
    // Переводим React useState hooks → TCA State

    @ObservableState
    struct State: Equatable {
        // Шаг 1 — выбор параметров (из siegblink: style picker + room picker)
        var selectedStyle: DesignStyle = .modern
        var selectedRoomType: RoomType = .livingRoom
        var userComment: String = ""
        var promptStrength: Float = 0.7   // как guidance_scale у adirik

        // Шаг 2 — фото (из siegblink: image upload)
        var sourceImage: UIImage? = nil
        var isShowingImagePicker: Bool = false
        var imageSource: ImageSource = .camera

        // Шаг 3 — processing (из siegblink: loading state)
        var phase: Phase = .idle
        var activeProvider: String? = nil  // "YandexGPT" / "GigaChat" / "CoreML"

        // Шаг 4 — результат (из siegblink: result display)
        var designAdvice: DesignAdvice? = nil
        var sliderPosition: Float = 0.5    // before/after слайдер

        // Chat history
        var chatMessages: [ChatMessage] = []
        var currentInput: String = ""

        // Флаги UI
        var isShowingFullResult: Bool = false
        var isShareSheetPresented: Bool = false

        enum Phase: Equatable {
            case idle
            case capturing           // открыта камера/галерея
            case processingImage     // ImagePreprocessor работает
            case awaitingAI          // запрос к AIProviderRouter
            case result
            case error(String)
        }

        enum ImageSource: Equatable {
            case camera
            case gallery
            case roomScan           // из RoomScanManager (Session 03)
        }
    }

    // MARK: — Action
    // Переводим React event handlers + API calls → TCA Actions

    enum Action: BindableAction {
        case binding(BindingAction<State>)

        // Выбор параметров
        case styleSelected(DesignStyle)
        case roomTypeSelected(RoomType)
        case promptStrengthChanged(Float)

        // Работа с изображением
        case imageSourceTapped(State.ImageSource)
        case imagePicked(UIImage)
        case imagePickerDismissed

        // Анализ (главная цепочка)
        case analyzeButtonTapped
        case imagePreprocessed(ProcessedImage)          // ImagePreprocessor готов
        case aiResponseReceived(DesignAdvice)           // AIProviderRouter вернул
        case aiError(AIError)

        // Чат
        case sendChatMessage
        case chatResponseReceived(String, String)       // (provider, message)

        // UI
        case sliderMoved(Float)
        case showFullResult
        case shareResult
        case resetToIdle
        case retryAnalysis
    }

    // MARK: — Dependencies
    @Dependency(\.aiAdvisorClient) var aiAdvisorClient
    @Dependency(\.imagePreprocessor) var imagePreprocessor

    // MARK: — Reducer
    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            // --- Выбор параметров (мгновенно, без side effects) ---
            case .styleSelected(let style):
                state.selectedStyle = style
                return .none

            case .roomTypeSelected(let type):
                state.selectedRoomType = type
                return .none

            case .promptStrengthChanged(let value):
                state.promptStrength = value
                return .none

            // --- Изображение ---
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
                if state.sourceImage == nil {
                    state.phase = .idle
                }
                return .none

            // --- Главная цепочка анализа ---
            // Паттерн из siegblink: upload → validate → AI call → show result
            case .analyzeButtonTapped:
                guard let image = state.sourceImage else { return .none }
                state.phase = .processingImage
                state.designAdvice = nil

                let request = DesignRequest(
                    roomType: state.selectedRoomType,
                    style: state.selectedStyle,
                    sourceImage: image,
                    userComment: state.userComment.isEmpty ? nil : state.userComment,
                    promptStrength: state.promptStrength
                )

                return .run { send in
                    // Шаг 1: препроцессинг (Session 03 — ImagePreprocessor)
                    let processed = try await imagePreprocessor.process(image)
                    await send(.imagePreprocessed(processed))

                    // Шаг 2: AI запрос через роутер (Session 02 — AIProviderRouter)
                    let advice = try await aiAdvisorClient.analyze(request, processed)
                    await send(.aiResponseReceived(advice))
                } catch: { error, send in
                    if let aiErr = error as? AIError {
                        await send(.aiError(aiErr))
                    } else {
                        await send(.aiError(.invalidResponse(provider: "unknown", details: error.localizedDescription)))
                    }
                }

            case .imagePreprocessed:
                state.phase = .awaitingAI
                return .none

            case .aiResponseReceived(let advice):
                state.phase = .result
                state.designAdvice = advice
                state.chatMessages.append(.init(
                    role: .assistant,
                    content: advice.summary
                ))
                return .none

            case .aiError(let error):
                state.phase = .error(error.localizedDescription)
                return .none

            // --- Чат ---
            case .sendChatMessage:
                guard !state.currentInput.isEmpty,
                      let advice = state.designAdvice else { return .none }
                let userMsg = state.currentInput
                state.chatMessages.append(.init(role: .user, content: userMsg))
                state.currentInput = ""

                let context = state.chatMessages
                return .run { send in
                    let (provider, reply) = try await aiAdvisorClient.chat(userMsg, context, advice)
                    await send(.chatResponseReceived(provider, reply))
                }

            case .chatResponseReceived(let provider, let message):
                state.activeProvider = provider
                state.chatMessages.append(.init(role: .assistant, content: message))
                return .none

            // --- UI actions ---
            case .sliderMoved(let pos):
                state.sliderPosition = pos
                return .none

            case .showFullResult:
                state.isShowingFullResult = true
                return .none

            case .shareResult:
                state.isShareSheetPresented = true
                return .none

            case .resetToIdle:
                state = State()
                return .none

            case .retryAnalysis:
                state.phase = .idle
                state.designAdvice = nil
                return .none

            case .binding:
                return .none
            }
        }
    }
}
```

---

## 3. Модель результата

### Файл: `Features/AIAdvisor/Models/DesignAdvice.swift`

```swift
// DesignAdvice.swift
// Аналог output от adirik/interior-design, но текстовый (YandexGPT не генерирует картинки)

import Foundation

struct DesignAdvice: Equatable, Codable, Sendable {
    let id: UUID
    let style: DesignStyle
    let roomType: RoomType
    let summary: String             // 2–3 предложения концепции
    let colorPalette: [ColorSuggestion]
    let furniturePieces: [FurniturePiece]
    let lightingTips: [String]
    let decorItems: [String]
    let budgetLevel: BudgetLevel
    let provider: String            // "YandexGPT" / "GigaChat" / "CoreML"
    let generatedAt: Date

    enum BudgetLevel: String, Codable, Sendable {
        case economy = "economy"
        case mid = "mid"
        case premium = "premium"

        var displayName: String {
            switch self {
            case .economy:  return "Эконом"
            case .mid:      return "Средний"
            case .premium:  return "Премиум"
            }
        }

        var priceRange: String {
            switch self {
            case .economy:  return "до 300 000 ₽"
            case .mid:      return "300 000 – 1 500 000 ₽"
            case .premium:  return "от 1 500 000 ₽"
            }
        }
    }
}

struct ColorSuggestion: Equatable, Codable, Sendable {
    let name: String      // "Серо-белый", "Дымчатый синий"
    let hex: String       // "#F5F5F0"
    let role: String      // "основной", "акцентный", "фоновый"
}

struct FurniturePiece: Equatable, Codable, Sendable {
    let name: String          // "Диван Ikea KIVIK"
    let category: String      // "мягкая мебель"
    let marketplace: String?  // "Wildberries", "Ozon" — для Session 07 (Marketplace)
    let approxPrice: String?  // "85 000 ₽"
}
```

---

## 4. AI Client Dependency

### Файл: `Features/AIAdvisor/AIAdvisorClient.swift`

```swift
// AIAdvisorClient.swift
// Dependency wrapper над AIProviderRouter — чистая изоляция слоёв

import ComposableArchitecture
import Foundation

// MARK: — Protocol
struct AIAdvisorClient: Sendable {
    var analyze: @Sendable (DesignRequest, ProcessedImage) async throws -> DesignAdvice
    var chat: @Sendable (String, [ChatMessage], DesignAdvice) async throws -> (String, String)
}

// MARK: — Live Implementation
extension AIAdvisorClient: DependencyKey {
    static var liveValue: AIAdvisorClient {
        AIAdvisorClient(
            analyze: { request, processedImage in
                // Используем AIProviderRouter из Session 02
                let router = await AIProviderRouter.shared

                let imageB64 = processedImage.jpegBase64

                // Промпт строим так же как siegblink строит prompt для Replicate:
                // style + room + user comment
                let prompt = request.buildYandexGPTPrompt()

                let aiPrompt = AIPrompt(
                    systemMessage: "Ты эксперт по дизайну интерьеров для российского рынка.",
                    userMessage: prompt,
                    imageBase64: imageB64,
                    maxTokens: 2000
                )

                let response = try await router.complete(prompt: aiPrompt)

                // Парсим структурированный ответ
                return try DesignAdviceParser.parse(
                    rawText: response.text,
                    style: request.style,
                    roomType: request.roomType,
                    provider: response.provider
                )
            },
            chat: { userMessage, history, advice in
                let router = await AIProviderRouter.shared

                // Контекст — предыдущий дизайн-совет + история чата
                let contextPrompt = """
                Контекст: ты уже дал рекомендации по дизайну интерьера в стиле \(advice.style.displayName)
                для \(advice.roomType.displayName).
                Краткая концепция: \(advice.summary)
                
                Пользователь задаёт уточняющий вопрос: \(userMessage)
                Отвечай кратко и по делу, на русском языке.
                """

                let prompt = AIPrompt(
                    systemMessage: "Ты профессиональный дизайнер интерьеров.",
                    userMessage: contextPrompt,
                    imageBase64: nil,
                    maxTokens: 500
                )

                let response = try await router.complete(prompt: prompt)
                return (response.provider, response.text)
            }
        )
    }

    // Mock для тестов
    static var testValue: AIAdvisorClient {
        AIAdvisorClient(
            analyze: { _, _ in
                DesignAdvice(
                    id: UUID(),
                    style: .modern,
                    roomType: .livingRoom,
                    summary: "Светлое современное пространство с акцентом на функциональность.",
                    colorPalette: [
                        ColorSuggestion(name: "Белый матовый", hex: "#F8F8F6", role: "основной"),
                        ColorSuggestion(name: "Тёпло-серый", hex: "#9E9E8E", role: "дополнительный"),
                        ColorSuggestion(name: "Дымчатый зелёный", hex: "#4A7C59", role: "акцентный")
                    ],
                    furniturePieces: [
                        FurniturePiece(name: "Диван KIVIK 3-местный", category: "мягкая мебель",
                                      marketplace: "Wildberries", approxPrice: "85 000 ₽")
                    ],
                    lightingTips: ["Трековые светильники на потолке"],
                    decorItems: ["Фикус", "Хлопковый плед"],
                    budgetLevel: .mid,
                    provider: "MockProvider",
                    generatedAt: Date()
                )
            },
            chat: { _, _, _ in ("MockProvider", "Рекомендую добавить зеркало для визуального расширения пространства.") }
        )
    }
}

extension DependencyValues {
    var aiAdvisorClient: AIAdvisorClient {
        get { self[AIAdvisorClient.self] }
        set { self[AIAdvisorClient.self] = newValue }
    }
}
```

---

## 5. SwiftUI Views

### Файл: `Features/AIAdvisor/AIAdvisorView.swift`

```swift
// AIAdvisorView.swift
// SwiftUI корневой экран — переводим структуру siegblink page.tsx

import SwiftUI
import ComposableArchitecture

struct AIAdvisorView: View {
    @Bindable var store: StoreOf<AIAdvisorFeature>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Блок 1: Выбор стиля (из siegblink: style picker)
                    StylePickerView(
                        selected: store.selectedStyle,
                        onSelect: { store.send(.styleSelected($0)) }
                    )

                    // Блок 2: Выбор типа комнаты (из siegblink: room type picker)
                    RoomTypePickerView(
                        selected: store.selectedRoomType,
                        onSelect: { store.send(.roomTypeSelected($0)) }
                    )

                    // Блок 3: Фото
                    PhotoInputView(store: store)

                    // Блок 4: Сила трансформации (из adirik: prompt_strength)
                    if store.sourceImage != nil {
                        PromptStrengthSlider(
                            value: store.promptStrength,
                            onChange: { store.send(.promptStrengthChanged($0)) }
                        )
                    }

                    // Блок 5: Дополнительное пожелание
                    TextField("Добавить пожелание...", text: $store.userComment)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    // Блок 6: Кнопка анализа
                    AnalyzeButton(store: store)

                    // Блок 7: Результат
                    if store.phase == .result, let advice = store.designAdvice {
                        DesignResultView(
                            advice: advice,
                            sourceImage: store.sourceImage,
                            sliderPosition: store.sliderPosition,
                            onSliderMove: { store.send(.sliderMoved($0)) },
                            onShare: { store.send(.shareResult) }
                        )

                        // Блок 8: Чат
                        ChatView(store: store)
                    }

                    // Error state
                    if case .error(let msg) = store.phase {
                        ErrorBanner(message: msg) {
                            store.send(.retryAnalysis)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("AI-Дизайнер")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if store.phase != .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сначала") { store.send(.resetToIdle) }
                    }
                }
            }
        }
        .sheet(isPresented: $store.isShowingImagePicker) {
            ImagePickerViewController(
                source: store.imageSource == .camera ? .camera : .photoLibrary,
                onImage: { store.send(.imagePicked($0)) },
                onCancel: { store.send(.imagePickerDismissed) }
            )
        }
    }
}
```

### Файл: `Features/AIAdvisor/Views/StylePickerView.swift`

```swift
// StylePickerView.swift
// Горизонтальный скролл стилей — аналог siegblink style selector
// В siegblink: chipы с иконками, здесь: карточки с эмодзи

import SwiftUI

struct StylePickerView: View {
    let selected: DesignStyle
    let onSelect: (DesignStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Стиль")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DesignStyle.allCases, id: \.self) { style in
                        StyleChip(
                            style: style,
                            isSelected: style == selected,
                            onTap: { onSelect(style) }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct StyleChip: View {
    let style: DesignStyle
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(style.emoji)
                    .font(.title2)
                Text(style.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
```

### Файл: `Features/AIAdvisor/Views/BeforeAfterSliderView.swift`

```swift
// BeforeAfterSliderView.swift
// ГЛАВНЫЙ паттерн из siegblink — сравнение до/после
// Реализация: драг-жест поверх двух изображений

import SwiftUI

struct BeforeAfterSliderView: View {
    let beforeImage: UIImage
    let afterDescription: DesignAdvice  // Вместо after-фото — цветовые блоки из AI
    @Binding var sliderPosition: Float  // 0.0 = всё "до", 1.0 = всё "после"

    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {

                // ПОСЛЕ — AI-визуализация (цвета + описание)
                AfterVisualizationView(advice: afterDescription)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ДО — оригинальное фото
                Image(uiImage: beforeImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width * CGFloat(sliderPosition), height: geo.size.height)
                    .clipped()

                // Разделитель
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: geo.size.height)
                    .offset(x: geo.size.width * CGFloat(sliderPosition) - 1.5)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                            .shadow(radius: 4)
                            .overlay(
                                Image(systemName: "arrow.left.and.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            )
                            .offset(x: geo.size.width * CGFloat(sliderPosition) - 16,
                                    y: geo.size.height / 2 - 16),
                        alignment: .topLeading
                    )

                // Лейблы ДО/ПОСЛЕ
                HStack {
                    Label("До", systemImage: "photo")
                        .font(.caption2.weight(.semibold))
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(8)
                    Spacer()
                    Label("После", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(8)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newPosition = Float(value.location.x / geo.size.width)
                        sliderPosition = max(0, min(1, newPosition))
                    }
            )
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Визуализация "После" — цветовая палитра из DesignAdvice
private struct AfterVisualizationView: View {
    let advice: DesignAdvice

    var body: some View {
        ZStack {
            // Фон — первый цвет палитры
            if let mainColor = advice.colorPalette.first {
                Color(hex: mainColor.hex)
            } else {
                Color(.systemGray6)
            }

            VStack(spacing: 8) {
                // Палитра
                HStack(spacing: 6) {
                    ForEach(advice.colorPalette, id: \.hex) { color in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: color.hex))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            Text(color.role)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text(advice.summary)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.primary)
            }
            .padding()
        }
    }
}
```

---

## 6. DesignAdviceParser

### Файл: `Features/AIAdvisor/DesignAdviceParser.swift`

```swift
// DesignAdviceParser.swift
// Парсит структурированный текстовый ответ от YandexGPT в DesignAdvice
// Аналог парсинга JSON-ответа от Replicate в siegblink

import Foundation

enum DesignAdviceParser {

    static func parse(
        rawText: String,
        style: DesignStyle,
        roomType: RoomType,
        provider: String
    ) throws -> DesignAdvice {

        // YandexGPT возвращает текст с нумерованными секциями 1–6
        // Парсим по заголовкам секций

        let sections = extractSections(from: rawText)

        let colorPalette = parseColors(from: sections[1] ?? "")
        let furniture = parseFurniture(from: sections[2] ?? "")
        let lighting = parseList(from: sections[3] ?? "")
        let decor = parseList(from: sections[4] ?? "")
        let budget = parseBudget(from: sections[5] ?? "")

        return DesignAdvice(
            id: UUID(),
            style: style,
            roomType: roomType,
            summary: sections[0] ?? rawText,
            colorPalette: colorPalette,
            furniturePieces: furniture,
            lightingTips: lighting,
            decorItems: decor,
            budgetLevel: budget,
            provider: provider,
            generatedAt: Date()
        )
    }

    private static func extractSections(from text: String) -> [Int: String] {
        var result: [Int: String] = [:]
        let lines = text.components(separatedBy: "\n")
        var currentSection = 0
        var currentContent: [String] = []

        for line in lines {
            if line.hasPrefix("1.") { currentSection = 0; currentContent = [] }
            else if line.hasPrefix("2.") { result[0] = currentContent.joined(separator: "\n"); currentSection = 1; currentContent = [] }
            else if line.hasPrefix("3.") { result[1] = currentContent.joined(separator: "\n"); currentSection = 2; currentContent = [] }
            else if line.hasPrefix("4.") { result[2] = currentContent.joined(separator: "\n"); currentSection = 3; currentContent = [] }
            else if line.hasPrefix("5.") { result[3] = currentContent.joined(separator: "\n"); currentSection = 4; currentContent = [] }
            else if line.hasPrefix("6.") { result[4] = currentContent.joined(separator: "\n"); currentSection = 5; currentContent = [] }
            else { currentContent.append(line) }
        }
        result[currentSection] = currentContent.joined(separator: "\n")
        return result
    }

    private static func parseColors(from text: String) -> [ColorSuggestion] {
        // TODO: Попросить YandexGPT отвечать строго в формате "Название #hex роль"
        // Временный парсер до промпт-инженеринга
        let fallbackPalette: [ColorSuggestion] = [
            ColorSuggestion(name: "Белый", hex: "#FFFFFF", role: "основной"),
            ColorSuggestion(name: "Серый", hex: "#808080", role: "дополнительный"),
            ColorSuggestion(name: "Акцент", hex: "#4A7C59", role: "акцентный")
        ]
        // TODO: реальный парсинг
        return fallbackPalette
    }

    private static func parseFurniture(from text: String) -> [FurniturePiece] {
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.map { line in
            FurniturePiece(
                name: line.trimmingCharacters(in: .whitespacesAndNewlines),
                category: "мебель",
                marketplace: detectMarketplace(in: line),
                approxPrice: extractPrice(from: line)
            )
        }
    }

    private static func parseList(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseBudget(from text: String) -> DesignAdvice.BudgetLevel {
        let lowercased = text.lowercased()
        if lowercased.contains("премиум") || lowercased.contains("premium") { return .premium }
        if lowercased.contains("эконом") || lowercased.contains("economy") { return .economy }
        return .mid
    }

    private static func detectMarketplace(in text: String) -> String? {
        if text.lowercased().contains("wildberries") || text.lowercased().contains("вб") { return "Wildberries" }
        if text.lowercased().contains("ozon") || text.lowercased().contains("озон") { return "Ozon" }
        if text.lowercased().contains("сбермегамаркет") { return "СберМегаМаркет" }
        return nil
    }

    private static func extractPrice(from text: String) -> String? {
        // Ищем паттерн: "85 000 ₽" или "85000 руб"
        let pattern = #"[\d\s]+[₽рублей]+"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
```

---

## 7. Тесты

### Файл: `AIVibeTests/AI/AIAdvisorFeatureTests.swift`

```swift
// AIAdvisorFeatureTests.swift
// Тесты TCA Reducer — аналог unit tests в siegblink

import ComposableArchitecture
import Testing
@testable import AIVibe

@MainActor
struct AIAdvisorFeatureTests {

    // Тест 1: Выбор стиля
    @Test
    func styleSelectionUpdatesState() async {
        let store = TestStore(
            initialState: AIAdvisorFeature.State()
        ) { AIAdvisorFeature() }

        await store.send(.styleSelected(.scandinavian)) {
            $0.selectedStyle = .scandinavian
        }
    }

    // Тест 2: Выбор типа комнаты
    @Test
    func roomTypeSelectionUpdatesState() async {
        let store = TestStore(
            initialState: AIAdvisorFeature.State()
        ) { AIAdvisorFeature() }

        await store.send(.roomTypeSelected(.bedroom)) {
            $0.selectedRoomType = .bedroom
        }
    }

    // Тест 3: Полный флоу анализа через mock
    @Test
    func analyzeFlowWithMockProvider() async {
        let store = TestStore(
            initialState: AIAdvisorFeature.State()
        ) {
            AIAdvisorFeature()
        } withDependencies: {
            $0.aiAdvisorClient = .testValue
            $0.imagePreprocessor = .testValue
        }

        await store.send(.imagePicked(UIImage())) {
            $0.sourceImage = UIImage()
        }

        await store.send(.analyzeButtonTapped) {
            $0.phase = .processingImage
        }

        await store.receive(\.imagePreprocessed) {
            $0.phase = .awaitingAI
        }

        await store.receive(\.aiResponseReceived) {
            $0.phase = .result
            $0.designAdvice != nil
            // Проверяем что в чате появилось сообщение
            $0.chatMessages.count == 1
        }
    }

    // Тест 4: Обработка ошибки AI
    @Test
    func errorStateOnAIFailure() async {
        let store = TestStore(
            initialState: AIAdvisorFeature.State()
        ) {
            AIAdvisorFeature()
        } withDependencies: {
            $0.aiAdvisorClient = AIAdvisorClient(
                analyze: { _, _ in throw AIError.allProvidersExhausted },
                chat: { _, _, _ in ("", "") }
            )
            $0.imagePreprocessor = .testValue
        }

        await store.send(.imagePicked(UIImage())) {
            $0.sourceImage = UIImage()
        }
        await store.send(.analyzeButtonTapped) {
            $0.phase = .processingImage
        }
        await store.receive(\.aiError) {
            if case .error = $0.phase {} else { Issue.record("Expected error phase") }
        }
    }

    // Тест 5: Reset очищает состояние
    @Test
    func resetResetsToInitialState() async {
        var initialState = AIAdvisorFeature.State()
        initialState.phase = .result
        initialState.selectedStyle = .loft

        let store = TestStore(initialState: initialState) { AIAdvisorFeature() }
        await store.send(.resetToIdle) {
            $0.phase = .idle
            $0.selectedStyle = .modern   // сброс до дефолта
        }
    }

    // Тест 6: DesignStyle.buildYandexGPTPrompt содержит нужные данные
    @Test
    func promptContainsStyleAndRoomType() {
        let request = DesignRequest(
            roomType: .bedroom,
            style: .scandinavian,
            sourceImage: UIImage(),
            userComment: "больше растений",
            promptStrength: 0.7
        )
        let prompt = request.buildYandexGPTPrompt()
        #expect(prompt.contains("скандинавский"))
        #expect(prompt.contains("спальня"))
        #expect(prompt.contains("растений"))
    }

    // Тест 7: DesignAdviceParser обрабатывает пустой ответ без краша
    @Test
    func parserHandlesEmptyInput() throws {
        let advice = try DesignAdviceParser.parse(
            rawText: "",
            style: .modern,
            roomType: .livingRoom,
            provider: "Test"
        )
        #expect(advice.style == .modern)
        #expect(advice.roomType == .livingRoom)
    }
}
```

---

## 8. Расширение для Polza IDE (промпт)

> Вставить в следующей сессии в Polza IDE с @PROJECT_RULES.md в контексте

```
Реализуй Feature AIAdvisor согласно SESSION_05_ai_advisor.md.

Создай все файлы в папке Features/AIAdvisor/:
1. Models/DesignStyle.swift
2. Models/RoomType.swift
3. Models/DesignRequest.swift
4. Models/DesignAdvice.swift
5. AIAdvisorFeature.swift (TCA Reducer)
6. AIAdvisorClient.swift (Dependency)
7. DesignAdviceParser.swift
8. AIAdvisorView.swift
9. Views/StylePickerView.swift
10. Views/RoomTypePickerView.swift
11. Views/PhotoInputView.swift
12. Views/BeforeAfterSliderView.swift
13. Views/DesignResultView.swift
14. Views/ChatBubbleView.swift

А также тесты в AIVibeTests/AI/AIAdvisorFeatureTests.swift

Следуй Swift 6, @Sendable везде, TCA patterns.
После создания файлов — запусти тесты через GitHub Actions.
```

---

## Связи с другими сессиями

| Сессия | Связь с AIAdvisor |
|--------|------------------|
| Session 02 (AIProviderRouter) | AIAdvisorClient.liveValue вызывает router.complete() |
| Session 03 (RoomScan) | sourceImage может приходить из RoomScanManager |
| Session 03 (ImagePreprocessor) | обязательный шаг перед AI запросом |
| Session 04 (Backend) | backend/index.js получает imageBase64 из DesignRequest |
| Session 07 (Marketplace) | FurniturePiece.marketplace → открывает WB/Ozon |

---

*SESSION_05 готова. Следующая: SESSION_06 — Portfolio Feature*
