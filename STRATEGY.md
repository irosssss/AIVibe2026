# AIVibe — Strategy Master File

## Changelog

| Дата | Версия | Изменения |
|------|--------|-----------|
| 2026-05-18 | 1.0 | Инициализация: стратегия, роадмап, агенты, анализы |
| 2026-05-18 | 1.1 | Добавлены: роадмап промтов W1-W6, агенты разработки, интеграционная карта, 5 расширенных анализов |

---

## 1. Стратегический документ (исходный)

> Составлено на основе анализа кодовой базы (Swift 6 / TCA / RoomPlan / Triplex AI Fallback / Yandex Cloud Backend).

### Текущее состояние (as-is)

| Компонент | Статус | Примечание |
|-----------|--------|-----------|
| AI Router (YandexGPT → GigaChat → CoreML) | ✅ Готов | Circuit Breaker: 3 ошибки → 5 мин пауза |
| CircuitBreaker (actor, thread-safe) | ✅ Готов | threshold=3, timeout=300s |
| AIError (12 case-ов) | ✅ Готов | |
| AIProviderRouter (Triplex + RAG) | ✅ Готов | |
| StorageClient, NetworkClient | ✅ Готов | |
| AppMetricaAnalytics | ✅ Готов | |
| AppDependencies (DI) | ✅ Готов | |
| AIAdvisorFeature (TCA + RAG) | ✅ Готов | Ждёт Mac для SwiftUI Preview |
| MarketplaceFeature (TCA + Apify) | ✅ Готов | Ждёт Mac |
| ImageGenClient (ARDesigner) | ✅ Готов | Ждёт Mac |
| RoomScan / ARDesigner | ✅ Готов | Ждёт Mac (LiDAR / RealityKit) |
| Backend: ai-advisor, marketplace, rag-indexer, image-gen | ✅ Готов | Yandex Cloud Functions |
| Backend: shared (yandexgpt, gigachat, rag, ydb) | ✅ Готов | |
| Unit-тесты AIProviderRouter | ✅ 12 тестов | |
| Portfolio / Marketplace View | ⚠️ Частично | Ждёт Mac |
| Лендинг (Next.js) | ✅ Готов | Не задеплоен |
| CI/CD (GitHub Actions) | ✅ Готов | lint → build → test |

**Критический вывод:** ядро готово на уровне кода. Главный блокер — Mac для запуска Xcode и тестирования LiDAR / RealityKit.

### 1.1 Проектирование

**P0 — Входной контракт AI-агента-дизайнера:**
- `RoomGeometry`: площадь, форма, высота потолков, количество окон / дверей / розеток
- Стиль: enum (`Scandinavian | Loft | Modern | Japanese | Minimalist`) + свободный текст
- Бюджет: диапазон в рублях (опционально)
- Ограничения: несущие стены, запрещённые зоны

**P0 — Выходной контракт:**
- JSON: `{ itemType, brand, article, position: {x,y,z}, rotation, usdz_url }`
- Текстовое объяснение на русском
- Confidence score (0–1)

**P0 — Метрики сканирования:**

| Метрика | Цель | Как измерять |
|---------|------|-------------|
| Полнота стен | > 95% периметра | Сравнение с ручным обмером |
| Точность площади | ±5% | Контрольный замер рулеткой |
| Время скана | < 60 сек / 20 м² | `CFAbsoluteTimeGetCurrent()` |
| Детектирование дверей/окон | > 90% | Ручная разметка датасета |
| Стабильность | > 99% сессий | Crashlytics |

**P1 — Гибридная архитектура:**
```
iOS: RoomScan → ScanAgent → AnalyzerAgent → (онлайн) CloudDesigner / (офлайн) CoreML → ARDesigner
Backend: Yandex Cloud Functions (ai-advisor, marketplace, rag-indexer, image-gen) + YDB + Object Storage
Правило: в облако уходит только геометрия, не фото/видео. Кеш 30 дней в StorageClient.
```

### 1.2 Пайплайн данных скана (ключевой пробел)

```
CapturedRoom
  → RoomGeometryExtractor  (парсинг стен/дверей/окон/розеток)
  → PromptBuilder           (геометрия → системный+user промпт)
  → AIProviderRouter        (уже есть)
  → DesignResponseParser    (JSON → DesignPlan с валидацией)
  → ARSceneBuilder          (USDZ объекты → RealityView)
```

**Файлы для создания:**

| Файл | Назначение | Оценка |
|------|-----------|--------|
| `Features/RoomScan/RoomGeometryExtractor.swift` | Парсинг `CapturedRoom` | 3 дня |
| `Features/RoomScan/PromptBuilder.swift` | Геометрия → AI-промпт | 2 дня |
| `Features/ARDesigner/DesignResponseParser.swift` | JSON LLM → объекты | 2 дня |
| `Features/ARDesigner/ARSceneBuilder.swift` | Объекты → RealityView | 3 дня |
| `Features/ARDesigner/CollisionDetector.swift` | Проверка пересечений | 1 день |

### 1.3 Монетизация

```
FREE:     3 скана/мес, 1 вариант, AR без экспорта, watermark
PRO:      599 ₽/мес | 4 990 ₽/год — безлимит, 3 варианта, экспорт USDZ+PDF
BUSINESS: 2 490 ₽/мес — CAD, white-label, API, приоритет AI < 5 сек
Pay-per:  HD-рендер 199 ₽, пакет 10 шт 990 ₽, доп. вариант 99 ₽
```

### 1.4 Система агентов

```
AgentOrchestrator (Swift Actor)
  ├── ScanAgent    → QualityReport (на устройстве, < 500 мс)
  ├── AnalyzerAgent→ RoomGeometry  (на устройстве, < 200 мс)
  ├── DesignerAgent→ DesignPlan    (Cloud Function, < 8 сек)
  └── RefineAgent  → RefinedPlan   (Cloud Function, < 5 сек)
```

### 1.5 Роадмап 6 месяцев

| Месяц | Фаза | Критерий выхода |
|-------|------|----------------|
| M1 | Foundation: пайплайн скан→AR | iPhone видит мебель в AR |
| M2 | MVP Core: backend + каталог + фидбек | Полный цикл работает |
| M3 | Internal Beta: TestFlight 20, StoreKit 2 | Crash-free > 99%, NPS > 50 |
| M4 | Closed Beta: 200 чел, HD-рендер, affiliate | Like rate > 65%, D7 > 20% |
| M5 | Open Beta 10K, лендинг, ASO | — |
| M6 | App Store Launch, B2B пилот | 1K DAU, 50 PRO-подписчиков |

---

## 2. Роадмап промтов для Claude Code по спринтам (W1–W6)

> Все промты готовы к копированию в Claude Code. Запускать на Mac с открытым проектом AIVibe в Xcode.

---

### НЕДЕЛЯ 1 — Пайплайн данных скана

---

#### W1/D1-2 — RoomGeometryExtractor

**Промт:**
```
Я разрабатываю iOS-приложение AIVibe (Swift 6, TCA, RoomPlan, iOS 26+).

Создай файл `AIVibe/Features/RoomScan/RoomGeometryExtractor.swift`.

КОНТЕКСТ:
- RoomScanFeature.swift уже получает CapturedRoom из RoomPlan и сохраняет как Data
- Нужен детерминированный парсер, который превращает CapturedRoom в типизированную структуру RoomGeometry
- Никаких LLM, только Swift-код

ТРЕБОВАНИЯ К ТИПАМ (создай в том же файле или отдельном RoomGeometry.swift):
```swift
struct RoomGeometry: Codable, Sendable, Equatable {
    let area: Double              // кв. метры
    let perimeter: Double         // метры
    let ceilingHeight: Double     // метры
    let walls: [WallGeometry]
    let doors: [DoorGeometry]
    let windows: [WindowGeometry]
    let outlets: [OutletGeometry]
    let normalizedOrigin: SIMD3<Float> // угол комнаты как (0,0,0)
}

struct WallGeometry: Codable, Sendable, Equatable {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let length: Double
    let height: Double
    let isExterior: Bool
}

struct DoorGeometry: Codable, Sendable, Equatable {
    let position: SIMD3<Float>
    let width: Double
    let height: Double
    let wallIndex: Int
}

struct WindowGeometry: Codable, Sendable, Equatable {
    let position: SIMD3<Float>
    let width: Double
    let height: Double
    let sillHeight: Double
    let wallIndex: Int
}

struct OutletGeometry: Codable, Sendable, Equatable {
    let position: SIMD3<Float>
    let wallIndex: Int
}
```

ТРЕБОВАНИЯ К RoomGeometryExtractor:
```swift
// Протокол для тестируемости
protocol RoomGeometryExtracting: Sendable {
    func extract(from capturedRoom: CapturedRoom) throws -> RoomGeometry
}

struct RoomGeometryExtractor: RoomGeometryExtracting {
    func extract(from capturedRoom: CapturedRoom) throws -> RoomGeometry
}
```

ЛОГИКА:
1. Фильтрация шума: отбросить поверхности площадью < 0.1 м²
2. Нормализация: определить минимальный угол комнаты как (0,0,0), все координаты пересчитать
3. Floor detection: найти самую нижнюю горизонтальную поверхность = пол
4. Ceiling detection: самая верхняя горизонтальная = потолок → ceilingHeight
5. Стены: вертикальные поверхности, упорядочить по индексу
6. Двери/окна: openings внутри стен, разделить по высоте sill (окно если sillHeight > 0.3 м)
7. Площадь: использовать площадь пола
8. Периметр: сумма длин стен

EDGE CASES (обязательно handle):
- Пустой список поверхностей → throw RoomGeometryError.noSurfaces
- Нет пола → throw RoomGeometryError.noFloorDetected
- Площадь < 4 м² → throw RoomGeometryError.roomTooSmall(area:)
- Нет стен (< 3) → throw RoomGeometryError.insufficientWalls(count:)

Создай enum RoomGeometryError: LocalizedError со всеми case-ами.

Файл начинается с комментария: // AIVibe/Features/RoomScan/RoomGeometryExtractor.swift — парсинг CapturedRoom в RoomGeometry

Следуй Swift 6: все типы Sendable, никаких force unwrap, никаких @unchecked Sendable.
```

**Ожидаемый результат:**
- `AIVibe/Features/RoomScan/RoomGeometryExtractor.swift` — экстрактор + типы + ошибки

**Критерий готовности:**
- `swift build` без ошибок и warning
- Все edge cases кидают правильные ошибки (проверить через тест ниже)

**Зависимости:**
- `AIVibe/Features/RoomScan/RoomScanFeature.swift` (уже есть)
- `RoomPlan` framework (iOS 26+)

---

#### W1/D3 — Тесты RoomGeometryExtractor

**Промт:**
```
Я разрабатываю iOS-приложение AIVibe (Swift 6, TCA). Только что создан RoomGeometryExtractor.

Создай `AIVibeTests/RoomScan/RoomGeometryExtractorTests.swift`.

Посмотри на существующие тесты AIVibeTests/AI/AIProviderRouterTests.swift как образец стиля.

Нужны тест-хелперы для создания mock CapturedRoom:
- `makeMockRoom(wallCount: Int, area: Double, hasDoors: Bool, hasWindows: Bool) -> CapturedRoom`
- Используй RoomPlan mock объекты или stub-данные

ТЕСТ-КЕЙСЫ (обязательные):

1. Happy path: стандартная комната 20м², 4 стены, 1 дверь, 2 окна
   - area == 20.0 (±0.1)
   - walls.count == 4
   - doors.count == 1
   - windows.count == 2
   - normalizedOrigin == .zero

2. Edge: пустой CapturedRoom → throws .noSurfaces

3. Edge: площадь 3 м² → throws .roomTooSmall

4. Edge: нет горизонтальных поверхностей → throws .noFloorDetected

5. Edge: 2 стены → throws .insufficientWalls(count: 2)

6. Нормализация: origin всегда (0,0,0), все координаты >= 0

7. L-образная комната: 6 стен, площадь корректная

8. Фильтрация шума: поверхность 0.05 м² должна быть проигнорирована

Используй `@Suite` и `@Test` (Swift Testing framework, как в существующих тестах).
```

**Ожидаемый результат:**
- `AIVibeTests/RoomScan/RoomGeometryExtractorTests.swift`

**Критерий готовности:** `swift test --filter RoomGeometryExtractorTests` — все тесты зелёные.

---

### НЕДЕЛЯ 2 — AI-пайплайн

---

#### W2/D1-2 — PromptBuilder

**Промт:**
```
Я разрабатываю AIVibe (Swift 6, TCA). Уже есть:
- AIVibe/Core/AI/AIModels.swift (AIPrompt, ChatMessage, AIResponse)
- AIVibe/Features/RoomScan/RoomGeometryExtractor.swift (RoomGeometry и все типы)

Создай `AIVibe/Features/RoomScan/PromptBuilder.swift`.

НАЗНАЧЕНИЕ: преобразует RoomGeometry + UserDesignPreferences в AIPrompt для отправки в AIProviderRouter.

ТИПЫ:

```swift
struct UserDesignPreferences: Codable, Sendable, Equatable {
    let style: DesignStyle           // уже есть в Features/AIAdvisor/DesignStyle.swift
    let budgetRange: ClosedRange<Int>? // в рублях, nil = любой
    let restrictions: [String]       // "нельзя трогать стену у окна", "есть кот"
    let additionalText: String?      // свободный текст от пользователя
}

protocol PromptBuilding: Sendable {
    func buildDesignPrompt(geometry: RoomGeometry, preferences: UserDesignPreferences) -> AIPrompt
    func buildRefinePrompt(currentDesign: DesignPlan, feedback: UserFeedback) -> AIPrompt
}

struct PromptBuilder: PromptBuilding { ... }
```

СИСТЕМНЫЙ ПРОМПТ (встрой как константу, на русском):
```
Ты — эксперт по дизайну интерьеров. Ты помогаешь расставить мебель в комнате.
Строительные нормы (обязательные):
- Проходы между мебелью: не менее 80 см
- Расстояние от мебели до стен: не менее 5 см
- Путь эвакуации к двери всегда свободен
Формат ответа: ТОЛЬКО валидный JSON без markdown-обёртки.
JSON схема: { "items": [...], "explanation": "...", "confidence": 0.0-1.0 }
Каждый item: { "itemType": "...", "brand": "...", "article": "...", "position": {"x":0,"y":0,"z":0}, "rotation": 0.0, "usdz_url": "" }
```

USER ПРОМПТ должен включать:
- Площадь комнаты, периметр, высота потолков
- Количество стен, дверей, окон (с позициями)
- Желаемый стиль
- Бюджет (если указан)
- Ограничения
- Дополнительный текст пользователя

Параметры AIPrompt:
- temperature: 0.7 для creative стилей (Loft, Modern), 0.4 для functional (Minimalist)
- maxTokens: 2000

Создай `UserFeedback` тип для buildRefinePrompt:
```swift
struct UserFeedback: Codable, Sendable {
    let dislikes: [String]  // ["слишком темно", "мало мебели"]
    let keepItems: [String] // itemType-ы которые понравились
    let freeText: String?
}
```

EDGE CASES:
- Пустые restrictions → не включать в промпт
- Нет бюджета → "бюджет не ограничен"
- Очень большая комната (> 50 м²) → добавить в промпт "большая площадь, расставь мебель зонированием"

Файл: // AIVibe/Features/RoomScan/PromptBuilder.swift — генерация AI-промптов из геометрии комнаты
```

**Ожидаемый результат:**
- `AIVibe/Features/RoomScan/PromptBuilder.swift`

**Критерий готовности:** `swift build` чисто, метод возвращает непустой `AIPrompt` с обоими сообщениями.

---

#### W2/D3 — CollisionDetector

**Промт:**
```
Я разрабатываю AIVibe (Swift 6). Создай `AIVibe/Features/ARDesigner/CollisionDetector.swift`.

НАЗНАЧЕНИЕ: проверяет, что объекты в DesignPlan не пересекаются между собой и не вылезают за стены.

ТИПЫ (создай в этом же файле):
```swift
struct FurnitureItem: Codable, Sendable, Equatable {
    let id: UUID
    let itemType: String      // "sofa", "table", "chair", ...
    let brand: String
    let article: String
    let position: SIMD3<Float>
    let rotation: Float       // в градусах, вокруг оси Y
    let size: SIMD3<Float>    // width, height, depth в метрах
    let usdz_url: String
}

struct DesignPlan: Codable, Sendable, Equatable {
    let id: UUID
    let items: [FurnitureItem]
    let explanation: String
    let confidence: Double
    let generatedAt: Date
    let providerName: String
}

struct CollisionReport: Sendable {
    let hasCollisions: Bool
    let collidingPairs: [(FurnitureItem, FurnitureItem)]
    let itemsOutOfBounds: [FurnitureItem]
    let blockedDoors: [DoorGeometry]   // проход к двери заблокирован
}

protocol CollisionDetecting: Sendable {
    func check(plan: DesignPlan, room: RoomGeometry) -> CollisionReport
}
```

ЛОГИКА:
1. AABB коллизии между каждой парой предметов (учитывай rotation)
2. Проверка выхода за периметр стен (с допуском 5 см)
3. Проверка прохода к дверям: свободная зона 80 см перед каждой дверью
4. Проверка минимальных проходов: 80 см между мебелью в проходных зонах

Файл: // AIVibe/Features/ARDesigner/CollisionDetector.swift
```

**Ожидаемый результат:**
- `AIVibe/Features/ARDesigner/CollisionDetector.swift` со всеми типами включая `FurnitureItem` и `DesignPlan`

---

### НЕДЕЛЯ 3 — AR-слой

---

#### W3/D1-2 — DesignResponseParser

**Промт:**
```
Я разрабатываю AIVibe (Swift 6). Уже есть:
- FurnitureItem, DesignPlan (в CollisionDetector.swift)
- AIResponse (в AIModels.swift)

Создай `AIVibe/Features/ARDesigner/DesignResponseParser.swift`.

НАЗНАЧЕНИЕ: парсит текстовый ответ от LLM (может содержать markdown, лишний текст) в DesignPlan.

```swift
enum DesignResponseError: LocalizedError {
    case emptyResponse
    case invalidJSON(String)
    case missingRequiredFields(String)
    case confidenceOutOfRange(Double)
    case noItems
}

protocol DesignResponseParsing: Sendable {
    func parse(response: AIResponse, providerName: String) throws -> DesignPlan
}

struct DesignResponseParser: DesignResponseParsing { ... }
```

ЛОГИКА:
1. Извлечь JSON из ответа: искать первый `{` и последний `}` (LLM может обернуть в markdown)
2. JSONDecoder с keyDecodingStrategy = .convertFromSnakeCase
3. Валидация:
   - items не пустой → иначе .noItems
   - confidence в диапазоне 0-1 → иначе .confidenceOutOfRange
   - у каждого item есть itemType и position → иначе .missingRequiredFields
4. Генерация UUID для каждого item
5. Если size не указан LLM → подставить дефолтный по itemType:
   - "sofa" → (2.2, 0.9, 0.95)
   - "table" → (1.2, 0.75, 0.8)
   - "chair" → (0.6, 0.9, 0.6)
   - default → (1.0, 1.0, 1.0)
6. Retry-логика: при .invalidJSON пробуем очистить ответ сильнее (убрать всё до `{`)

Создай тесты в `AIVibeTests/ARDesigner/DesignResponseParserTests.swift`:
- Парсинг валидного JSON
- Парсинг JSON обёрнутого в ```json ... ```
- Пустой ответ → throws .emptyResponse
- JSON без items → throws .noItems
- Дефолтные размеры подставляются
- Confidence 1.5 → throws .confidenceOutOfRange

Файл: // AIVibe/Features/ARDesigner/DesignResponseParser.swift
```

**Ожидаемый результат:**
- `AIVibe/Features/ARDesigner/DesignResponseParser.swift`
- `AIVibeTests/ARDesigner/DesignResponseParserTests.swift`

**Критерий готовности:** все тесты зелёные, `swift build` чисто.

---

#### W3/D3-4 — ARSceneBuilder

**Промт:**
```
Я разрабатываю AIVibe (Swift 6, RealityKit, iOS 26+). Уже есть FurnitureItem, DesignPlan, RoomGeometry.

Создай `AIVibe/Features/ARDesigner/ARSceneBuilder.swift`.

НАЗНАЧЕНИЕ: преобразует DesignPlan + RoomGeometry в RealityKit сцену для RealityView.

```swift
@MainActor
protocol ARSceneBuilding {
    func buildScene(plan: DesignPlan, room: RoomGeometry) async throws -> RealityViewContent
    func updateScene(content: inout RealityViewContent, plan: DesignPlan, room: RoomGeometry) async throws
}

enum ARSceneError: LocalizedError {
    case usdz_loadFailed(String)
    case invalidPosition(FurnitureItem)
    case sceneSetupFailed(String)
}
```

ЛОГИКА:
1. Создать плоскость пола: `ModelEntity` прямоугольник по размерам комнаты, полупрозрачный материал
2. Для каждого FurnitureItem:
   a. Попытаться загрузить USDZ: `try await ModelEntity(named: item.usdz_url)`
   b. Если не найден → загрузить placeholder box с цветом по itemType
   c. Установить position: `entity.position = item.position`
   d. Установить rotation: `entity.orientation = simd_quatf(angle: item.rotation * .pi / 180, axis: [0,1,0])`
   e. Добавить collision shapes для взаимодействия
3. Создать anchor на поверхности пола
4. Добавить DirectionalLight + AmbientLight

PLACEHOLDER ЦВЕТА по itemType:
- sofa → blue, table → brown, chair → orange, bed → purple, wardrobe → gray, default → white

Создай `ARDesignerView.swift` (SwiftUI) с RealityView:
```swift
struct ARDesignerView: View {
    let plan: DesignPlan
    let room: RoomGeometry
    // RealityView с ARSceneBuilder
    // Overlay: список предметов внизу + кнопка "Изменить дизайн"
}
```

Файл: // AIVibe/Features/ARDesigner/ARSceneBuilder.swift — построение RealityKit сцены из DesignPlan

ВАЖНО: @MainActor для всего что касается UI и RealityKit. Загрузка USDZ через async/await.
```

**Ожидаемый результат:**
- `AIVibe/Features/ARDesigner/ARSceneBuilder.swift`
- `AIVibe/Features/ARDesigner/ARDesignerView.swift`

**Критерий готовности:** SwiftUI Preview показывает ARDesignerView без краша (с mock данными).

---

### НЕДЕЛЯ 4 — Агенты

---

#### W4/D1 — ScanAgent

**Промт:**
```
Я разрабатываю AIVibe (Swift 6). Уже есть RoomGeometryExtractor, RoomGeometry, RoomGeometryError.

Создай `AIVibe/Features/RoomScan/ScanAgent.swift`.

```swift
struct QualityReport: Sendable, Equatable {
    let score: Double          // 0.0 – 1.0
    let issues: [ScanIssue]
    let canProceed: Bool       // true если score >= 0.6 и нет критических issues
}

enum ScanIssue: Sendable, Equatable {
    case wallCompletenessLow(percent: Double)   // < 80%
    case roomTooSmall(area: Double)             // < 4 м²
    case noFloor
    case insufficientWalls(count: Int)
    case highNoise(outlierPercent: Double)      // > 5%
    case partialScan                            // < 4 поверхностей вообще
}

protocol ScanAgentProtocol: Sendable {
    func check(_ capturedRoom: CapturedRoom) async -> QualityReport
}

actor ScanAgent: ScanAgentProtocol {
    private let extractor: any RoomGeometryExtracting
    init(extractor: any RoomGeometryExtracting = RoomGeometryExtractor())
    func check(_ capturedRoom: CapturedRoom) async -> QualityReport
}
```

ЛОГИКА score:
- Начальный score: 1.0
- wallCompleteness < 80%: -0.3, < 60%: -0.5
- area < 4 м²: score = 0 (критическая ошибка)
- noFloor: score = 0 (критическая)
- insufficientWalls: -0.2 за каждую недостающую стену
- highNoise > 5%: -0.1

canProceed = score >= 0.6 и нет критических ошибок (roomTooSmall, noFloor)

Тесты в `AIVibeTests/RoomScan/ScanAgentTests.swift`:
- Хорошая комната → score > 0.9, canProceed = true
- Маленькая комната → canProceed = false
- Нет пола → canProceed = false
- 3 стены вместо 4 → score снижается
- Шум 6% → предупреждение в issues

Файл: // AIVibe/Features/RoomScan/ScanAgent.swift — валидация качества скана
```

---

#### W4/D2 — AnalyzerAgent

**Промт:**
```
Я разрабатываю AIVibe (Swift 6). Уже есть RoomGeometryExtractor, RoomGeometry.

Создай `AIVibe/Features/RoomScan/AnalyzerAgent.swift`.

```swift
protocol AnalyzerAgentProtocol: Sendable {
    func extract(_ capturedRoom: CapturedRoom) async throws -> RoomGeometry
}

// Тонкая обёртка над RoomGeometryExtractor с логированием и метриками
actor AnalyzerAgent: AnalyzerAgentProtocol {
    private let extractor: any RoomGeometryExtracting
    private let analytics: any AnalyticsLogging
    private let logger: Logger

    func extract(_ capturedRoom: CapturedRoom) async throws -> RoomGeometry {
        // 1. Замерить время
        // 2. Вызвать extractor.extract
        // 3. Залогировать в analytics: "room_analyzed" { area, wallCount, doorCount, duration }
        // 4. Вернуть результат или пробросить ошибку с логированием
    }
}
```

Добавь в `App/DI/AppDependencies.swift` создание AnalyzerAgent как @Dependency.

Файл: // AIVibe/Features/RoomScan/AnalyzerAgent.swift — обёртка над RoomGeometryExtractor с аналитикой
```

---

#### W4/D3-4 — AgentOrchestrator

**Промт:**
```
Я разрабатываю AIVibe (Swift 6, TCA). Уже есть:
- ScanAgent (actor, check(_ capturedRoom) -> QualityReport)
- AnalyzerAgent (actor, extract(_ capturedRoom) -> RoomGeometry)
- AIProviderRouter (complete(prompt:) -> AIResponse)
- PromptBuilder (buildDesignPrompt, buildRefinePrompt)
- DesignResponseParser (parse(response:) -> DesignPlan)
- CollisionDetector (check(plan:room:) -> CollisionReport)

Создай `AIVibe/Core/Agents/AgentOrchestrator.swift`.

```swift
enum AgentError: LocalizedError {
    case scanQualityInsufficient(issues: [ScanIssue])
    case designGenerationFailed(underlying: Error)
    case allRetriesExhausted(attempts: Int)
    case refinementFailed(underlying: Error)
}

actor AgentOrchestrator {
    private let scanAgent: any ScanAgentProtocol
    private let analyzerAgent: any AnalyzerAgentProtocol
    private let aiRouter: AIProviderRouter
    private let promptBuilder: any PromptBuilding
    private let parser: any DesignResponseParsing
    private let collisionDetector: any CollisionDetecting
    private let analytics: any AnalyticsLogging
    private let logger: Logger

    // ГЛАВНЫЙ ПАЙПЛАЙН
    func runDesignPipeline(
        room: CapturedRoom,
        preferences: UserDesignPreferences
    ) async throws -> DesignPlan {
        // 1. Проверка качества скана
        let quality = await scanAgent.check(room)
        guard quality.canProceed else {
            analytics.log(event: "pipeline_scan_rejected", params: [:])
            throw AgentError.scanQualityInsufficient(issues: quality.issues)
        }

        // 2. Извлечение геометрии
        let geometry = try await analyzerAgent.extract(room)

        // 3. Генерация дизайна (с retry до 2 раз при коллизиях)
        return try await generateWithRetry(geometry: geometry, preferences: preferences, maxAttempts: 2)
    }

    // РЕФАЙН ПАЙПЛАЙН
    func refine(
        plan: DesignPlan,
        room: RoomGeometry,
        feedback: UserFeedback
    ) async throws -> DesignPlan

    // ПРИВАТНЫЕ МЕТОДЫ
    private func generateWithRetry(
        geometry: RoomGeometry,
        preferences: UserDesignPreferences,
        maxAttempts: Int
    ) async throws -> DesignPlan {
        // При коллизиях добавляем в промпт информацию о проблеме и повторяем
    }
}
```

Добавь TCA Dependency:
```swift
extension DependencyValues {
    var agentOrchestrator: AgentOrchestrator { get set }
}
```

Тесты в `AIVibeTests/Agents/AgentOrchestratorTests.swift`:
- Happy path: все агенты отвечают → DesignPlan возвращается
- ScanAgent возвращает canProceed=false → throws .scanQualityInsufficient
- DesignerAgent падает 2 раза → throws .allRetriesExhausted
- CollisionDetector находит коллизии → retry с другим промптом

Файл: // AIVibe/Core/Agents/AgentOrchestrator.swift — оркестратор пайплайна скан→дизайн
```

**Ожидаемый результат:**
- `AIVibe/Core/Agents/AgentOrchestrator.swift`
- `AIVibeTests/Agents/AgentOrchestratorTests.swift`

---

### НЕДЕЛЯ 5 — Backend Cloud Functions

---

#### W5/D1-2 — /design/generate Cloud Function

**Промт:**
```
Я разрабатываю AIVibe. У нас есть Yandex Cloud Functions (Node.js 20).
Уже существуют: backend/shared/yandexgpt.js, gigachat.js, ydb-client.js, secrets.js

Создай `backend/functions/design-generate/index.js`.

ENDPOINT: POST /design/generate

INPUT (JSON body):
```json
{
  "userId": "string",
  "sessionId": "string",
  "geometry": {
    "area": 25.5,
    "perimeter": 20.0,
    "ceilingHeight": 2.7,
    "walls": [...],
    "doors": [...],
    "windows": [...]
  },
  "preferences": {
    "style": "Scandinavian",
    "budgetRange": { "min": 50000, "max": 200000 },
    "restrictions": ["нельзя занимать угол у окна"],
    "additionalText": "нужен диван для двоих"
  }
}
```

OUTPUT:
```json
{
  "designId": "uuid",
  "items": [...],
  "explanation": "...",
  "confidence": 0.85,
  "providerUsed": "YandexGPT",
  "generatedAt": "ISO8601"
}
```

ЛОГИКА:
1. Валидация входа (geometry обязателен, preferences опционален)
2. Сформировать системный промпт (строительные нормы, JSON-схема ответа)
3. Сформировать user промпт из geometry + preferences
4. Triplex Fallback: YandexGPT → GigaChat → заглушка (простейшая расстановка)
5. Парсинг JSON из ответа LLM
6. Сохранить в YDB: таблица `designs` (userId, sessionId, designId, geometry, result, timestamp)
7. Вернуть результат

ОБРАБОТКА ОШИБОК:
- 400: невалидный input
- 503: все провайдеры недоступны (но всегда пробуй заглушку)
- 500: ошибка YDB

Используй async/await (Node.js 20). Логируй через console.log в формате JSON.
Секреты через `backend/shared/secrets.js` (Yandex Lockbox).

Создай `backend/functions/design-generate/package.json` с зависимостями.
```

**Ожидаемый результат:**
- `backend/functions/design-generate/index.js`
- `backend/functions/design-generate/package.json`

---

#### W5/D3 — /design/refine Cloud Function

**Промт:**
```
Я разрабатываю AIVibe. Уже есть backend/functions/design-generate/index.js.

Создай `backend/functions/design-refine/index.js`.

INPUT:
```json
{
  "userId": "string",
  "designId": "string (предыдущий дизайн из YDB)",
  "feedback": {
    "dislikes": ["слишком темно", "мало мебели"],
    "keepItems": ["sofa", "table"],
    "freeText": "хочу добавить кресло у окна"
  }
}
```

ЛОГИКА:
1. Загрузить предыдущий дизайн из YDB по designId
2. Сформировать промпт: "вот текущий дизайн, пользователь недоволен X, сохрани Y, улучши"
3. keepItems включить в системный промпт как "эти предметы оставить без изменений"
4. Triplex Fallback
5. Сохранить как новую версию (parent_design_id = предыдущий designId)
6. Лимит истории: max 10 итераций на сессию

Схема YDB для истории:
```
designs:
  designId (PK), userId, sessionId, parentDesignId?,
  geometry (JSON), preferences (JSON), result (JSON),
  createdAt, iterationNumber
```
```

---

### НЕДЕЛЯ 6 — Полировка пайплайна

---

#### W6/D1-2 — RoomScanFeature: интеграция пайплайна

**Промт:**
```
Я разрабатываю AIVibe (Swift 6, TCA). Уже есть:
- AIVibe/Features/RoomScan/RoomScanFeature.swift (базовый, получает Data из RoomPlan)
- AgentOrchestrator (actor)
- UserDesignPreferences

Модифицируй RoomScanFeature.swift (НЕ пересоздавай с нуля):

1. Добавь в State:
```swift
public var qualityReport: QualityReport? = nil
public var geometry: RoomGeometry? = nil
public var designPreferences: UserDesignPreferences? = nil
public var isGeneratingDesign: Bool = false
public var designPlan: DesignPlan? = nil
public var designError: String? = nil
```

2. Добавь в Action:
```swift
case scanQualityChecked(QualityReport)
case geometryExtracted(RoomGeometry)
case preferencesSet(UserDesignPreferences)
case generateDesign
case designGenerated(DesignPlan)
case designGenerationFailed(String)
```

3. В Reducer добавь обработку новых actions, используя @Dependency agentOrchestrator.

4. .generateDesign должен запускать Effect:
```swift
.run { [geometry, preferences] send in
    guard let geometry, let preferences else { return }
    do {
        // Нужен CapturedRoom — передавай через State или отдельный Effect
        let plan = try await agentOrchestrator.runDesignPipeline(room: ..., preferences: preferences)
        await send(.designGenerated(plan))
    } catch {
        await send(.designGenerationFailed(error.localizedDescription))
    }
}
```

5. Обнови RoomScanView.swift: после успешного скана показывать ScanQualityView (score, issues), затем StylePickerView (выбор стиля), затем кнопку "Создать дизайн".

Создай `AIVibe/Features/RoomScan/StylePickerView.swift`:
- Горизонтальный ScrollView с карточками стилей (Scandinavian, Loft, Modern, Japanese, Minimalist)
- Слайдер бюджета (опционально)
- Текстовое поле "Дополнительные пожелания"
- Кнопка "Создать дизайн" → dispatch .generateDesign
```

**Ожидаемый результат:**
- Изменённый `RoomScanFeature.swift`
- `AIVibe/Features/RoomScan/StylePickerView.swift`

**Критерий готовности:** полный флоу в Simulator без краша: скан → качество → стиль → дизайн (с mock данными).

---

## 3. Архитектура агентов разработки для Claude Code

> 5 специализированных агентов. Каждый — готовый промт для вызова в новой сессии Claude Code.

---

### Агент 1 — Arch Agent (Архитектурный)

**Роль:** принимает решение о структуре, протоколах, DI, соответствии TCA.

**Промт для вызова:**
```
Ты — технический архитектор iOS-приложения AIVibe (Swift 6, TCA, RoomPlan, iOS 26+).

СУЩЕСТВУЮЩИЕ ПАТТЕРНЫ (следуй им строго):
- Все внешние зависимости имеют протоколы: AIProviderProtocol, RoomGeometryExtracting, CollisionDetecting
- DI через TCA @Dependency: extension DependencyValues { var X: XProtocol }
- Всё что Sendable используется cross-actor → помечай явно
- Actors для состояния, Structs для данных, Enums для ошибок
- Каждый файл = одна ответственность
- Тесты пишутся в той же итерации, что и код

КОНТЕКСТ ПРОЕКТА:
[вставь сюда содержимое PROJECT_RULES_v2.md]

МОЙ ВОПРОС:
[опиши задачу, например: "Нужно добавить кеширование результатов дизайна в StorageClient"]

Дай:
1. Архитектурное решение (протокол? struct? actor?)
2. Пример аналогичного паттерна в проекте
3. Список файлов которые нужно создать/изменить
4. Сигнатуры публичного API (без реализации)
5. Какие существующие протоколы переиспользовать
```

**Когда вызывать:** перед началом любой новой фичи, перед добавлением нового типа, при сомнениях в структуре.

---

### Агент 2 — Code Agent (Кодовый)

**Роль:** пишет Swift / Node.js код по спецификации.

**Промт для вызова:**
```
Ты — iOS-разработчик AIVibe (Swift 6, TCA, iOS 26+).

ПРАВИЛА КОДА:
- Swift 6 strict: все типы Sendable, actor-изоляция явная
- Никаких force unwrap, @unchecked Sendable без комментария
- Файл начинается: // путь/к/файлу.swift — назначение (на русском)
- Комментарии на русском, идентификаторы на английском
- Протоколы для всех внешних зависимостей (для тестируемости)
- Один файл = одна ответственность
- TCA: @Reducer, @ObservableState, Effect, @Dependency

СУЩЕСТВУЮЩИЙ КОД (переиспользуй, не дублируй):
- AIProviderRouter (complete(prompt:), analyzeImage(_:prompt:))
- AIError (12 case-ов — смотри AIError.swift)
- AIPrompt, AIResponse, ChatMessage (AIModels.swift)
- AnalyticsLogging protocol (AppMetricaAnalytics.swift)
- StorageClient, NetworkClient

ЗАДАЧА:
[вставь спецификацию из роадмапа промтов — секция "Промт" выше]

Напиши полную реализацию. Без "заглушек" и "TODO" — только готовый production-код.
```

**Когда вызывать:** когда архитектурное решение уже принято (Arch Agent отработал).

---

### Агент 3 — Test Agent (Тестовый)

**Промт для вызова:**
```
Ты — QA-инженер iOS-приложения AIVibe (Swift 6, Swift Testing framework).

ОБРАЗЕЦ СТИЛЯ (следуй ему):
[вставь содержимое AIVibeTests/AI/AIProviderRouterTests.swift]

ПРАВИЛА:
- Используй @Suite и @Test (НЕ XCTestCase)
- Моки создавай как struct/actor реализующие протоколы
- Проверяй happy path, все error cases, граничные значения
- Имена тестов — полные предложения на русском: "Первый провайдер падает → второй отвечает"
- Не мокируй то, что можно протестировать реально

КОД ДЛЯ ТЕСТИРОВАНИЯ:
[вставь код из Code Agent]

ПРОТОКОЛЫ ДЛЯ МОКИРОВАНИЯ:
[вставь список протоколов из файла]

Напиши полный тест-файл. Покрой:
1. Happy path
2. Все error enum cases
3. Граничные значения (пустые массивы, ноль, максимальные значения)
4. Concurrency: проверь что actor-методы не вызываются из неправильного контекста
```

---

### Агент 4 — Refactor Agent (Рефакторный)

**Промт для вызова:**
```
Ты — Swift 6 эксперт, рефакторишь код AIVibe.

ПРАВИЛА SWIFT 6:
- Все Sendable проверяются компилятором — никаких @unchecked без веской причины
- Actor-изоляция: UI только на @MainActor
- Нет data races: mutable state только внутри actor
- Prefer value types (struct) над reference types (class) где возможно

КОД ДЛЯ РЕФАКТОРИНГА:
[вставь проблемный файл или участок кода]

ПРОБЛЕМА (опционально):
[опиши warning или ошибку компилятора]

Сделай:
1. Исправь все Swift 6 warning-и и ошибки
2. Убери дублирование
3. Улучши читаемость (переименуй если нужно)
4. Не меняй публичный API без явного указания
5. Объясни каждое изменение в 1 строке комментария
```

---

### Агент 5 — Prompt Engineer Agent (Промпт-инженер)

**Промт для вызова:**
```
Ты — эксперт по промпт-инжинирингу для российских LLM (YandexGPT 5, GigaChat-Max).

ТЕКУЩИЙ СИСТЕМНЫЙ ПРОМПТ:
[вставь текущий системный промпт из PromptBuilder.swift]

ДАННЫЕ ФИДБЕКА (последние 7 дней):
- Like rate: [X]%
- Топ причин дизлайков: [список]
- Примеры плохих ответов: [примеры JSON от LLM]
- Примеры хороших ответов: [примеры]

ЗАДАЧА:
1. Найди причины плохих ответов (слишком много мебели / мало / странные позиции)
2. Предложи 2 варианта улучшенного системного промпта (A и B)
3. Объясни чем A отличается от B
4. Составь план A/B теста: метрика успеха, размер выборки, длительность

ОГРАНИЧЕНИЯ:
- Промпт должен работать на YandexGPT И GigaChat (избегай специфичных для одного инструкций)
- Максимум 800 токенов в системном промпте
- Ответ LLM должен быть валидным JSON без markdown обёртки
```

---

### Схема оркестрации агентов

```
Типичная задача → порядок вызова:

1. НОВАЯ ФИЧА:
   Arch Agent → (принимает решение) → Code Agent → Test Agent
   
2. БАГ / ОШИБКА КОМПИЛЯТОРА:
   Refactor Agent → (если нужны тесты) → Test Agent
   
3. УЛУЧШЕНИЕ AI-КАЧЕСТВА:
   Prompt Engineer Agent → Code Agent (обновить PromptBuilder.swift)

4. REVIEW кода:
   Refactor Agent (передать файл без задачи) → "найди проблемы"
```

**Передача контекста между агентами:**
- Через файлы проекта (Code Agent пишет файл, Test Agent его читает)
- Через явное копирование в промт (вставь код из предыдущего агента)
- Через STRATEGY.md Секцию 8 "Принятые решения"

---

## 4. Интеграционная карта

### 4.1 Существующие протоколы и типы — переиспользовать

| Тип / Протокол | Файл | Как использовать |
|----------------|------|-----------------|
| `AIProviderProtocol` | `Core/AI/AIProvider.swift` | Базовый протокол для моков в тестах |
| `AIProviderRouter` | `Core/AI/AIProviderRouter.swift` | Вызывать через `@Dependency \.aiRouter` |
| `AIError` | `Core/AI/AIError.swift` | Пробрасывать, не создавать новые сетевые ошибки |
| `AIPrompt`, `AIResponse`, `ChatMessage` | `Core/AI/AIModels.swift` | Вход/выход PromptBuilder и DesignResponseParser |
| `AnalyticsLogging` | `Core/Analytics/AppMetricaAnalytics.swift` | Логировать события агентов |
| `StorageClient` | `Core/Storage/StorageClient.swift` | Кешировать DesignPlan на устройстве |
| `NetworkClient` | `Core/Network/NetworkClient.swift` | HTTP-запросы к backend Cloud Functions |
| `DesignStyle` | `Features/AIAdvisor/DesignStyle.swift` | Переиспользовать в UserDesignPreferences |
| `NoopAnalytics` | `Core/AI/AIProviderRouter.swift` | Использовать в unit-тестах |

---

### 4.2 Файлы для создания с нуля

```
AIVibe/
├── Core/
│   └── Agents/
│       └── AgentOrchestrator.swift         ← W4
├── Features/
│   ├── RoomScan/
│   │   ├── RoomGeometryExtractor.swift     ← W1 (+ RoomGeometry типы)
│   │   ├── PromptBuilder.swift             ← W2
│   │   ├── ScanAgent.swift                 ← W4
│   │   ├── AnalyzerAgent.swift             ← W4
│   │   └── StylePickerView.swift           ← W6
│   └── ARDesigner/
│       ├── CollisionDetector.swift         ← W2 (+ FurnitureItem, DesignPlan типы)
│       ├── DesignResponseParser.swift      ← W3
│       ├── ARSceneBuilder.swift            ← W3
│       └── ARDesignerView.swift            ← W3

AIVibeTests/
├── RoomScan/
│   ├── RoomGeometryExtractorTests.swift    ← W1
│   └── ScanAgentTests.swift               ← W4
├── ARDesigner/
│   └── DesignResponseParserTests.swift     ← W3
└── Agents/
    └── AgentOrchestratorTests.swift        ← W4

backend/
└── functions/
    ├── design-generate/
    │   ├── index.js                        ← W5
    │   └── package.json                   ← W5
    └── design-refine/
        ├── index.js                        ← W5
        └── package.json                   ← W5
```

---

### 4.3 Файлы для модификации

| Файл | Что добавить |
|------|-------------|
| `App/DI/AppDependencies.swift` | Создание `AgentOrchestrator`, `ScanAgent`, `AnalyzerAgent`, `PromptBuilder`, `DesignResponseParser`, `CollisionDetector` |
| `Features/RoomScan/RoomScanFeature.swift` | Новые State поля, новые Actions, эффекты для генерации дизайна |
| `Features/RoomScan/RoomScanView.swift` | Новые секции: ScanQualityView, StylePickerView, DesignResultView |
| `Package.swift` | Ничего нового — все фреймворки уже есть |

---

### 4.4 Файлы НЕ ТРОГАТЬ

```
AIVibe/Core/AI/AIError.swift               — стабильный, 12 case-ов
AIVibe/Core/AI/AIModels.swift              — стабильный
AIVibe/Core/AI/AIProvider.swift            — протокол, не меняем
AIVibe/Core/AI/AIProviderRouter.swift      — стабильный
AIVibe/Core/AI/CircuitBreaker.swift        — стабильный
AIVibe/Core/AI/Providers/*.swift           — провайдеры работают
AIVibeTests/AI/AIProviderRouterTests.swift — 12 тестов, не трогать
backend/shared/*.js                         — стабильные модули
backend/functions/ai-advisor/index.js      — работает
backend/functions/marketplace/index.js     — работает
backend/functions/rag-indexer/index.js     — работает
demo-design-mg/                             — отдельный проект
```

---

## 5. Расширенные анализы

### 5.1 Производительность — узкие места

**Топ-5 источников задержек в сценарии скан→дизайн→AR:**

| Операция | Ожидаемая задержка | Решение |
|----------|-------------------|---------|
| RoomPlan скан | 30–90 сек | Нельзя ускорить, показывать live-feedback прогресса |
| YandexGPT API call | 3–10 сек | Streaming SSE, показывать текст по мере генерации |
| USDZ загрузка (5–10 предметов) | 2–8 сек | Параллельная загрузка + локальный кеш |
| RoomGeometryExtractor | < 100 мс | Уже OK, не блокирующий |
| CollisionDetector | < 50 мс | Уже OK |

**Параллелизация через `async let`:**

```swift
// В AgentOrchestrator — ScanAgent и начало UI можно запустить параллельно
async let qualityReport = scanAgent.check(capturedRoom)
async let uiAnimationDone = showProcessingAnimation()
let (quality, _) = await (qualityReport, uiAnimationDone)
```

```swift
// ARSceneBuilder — параллельная загрузка USDZ
func loadAllEntities(items: [FurnitureItem]) async throws -> [ModelEntity] {
    try await withThrowingTaskGroup(of: (Int, ModelEntity).self) { group in
        for (i, item) in items.enumerated() {
            group.addTask { (i, try await self.loadEntity(for: item)) }
        }
        var results = [(Int, ModelEntity)]()
        for try await result in group { results.append(result) }
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
```

**Где показывать прогресс-бар vs скелетон:**
- Скан (30–90 сек): анимированный лайв-вид с RoomPlan framework
- Генерация дизайна (3–10 сек): скелетон карточки + streaming текст объяснения
- Загрузка USDZ (2–8 сек): placeholder boxes сразу, подменять по мере загрузки

**Кеширование:**
- `DesignPlan` в `StorageClient` по ключу `hash(geometry + preferences)` — TTL 30 дней
- USDZ файлы — NSCache в памяти + файловый кеш (Kingfisher уже подключён)
- Системный промпт — константа в PromptBuilder (не загружать с сервера)

**Метрика Time-to-First-Design:**
```swift
// В AppMetricaAnalytics — замерять:
analytics.log(event: "design_pipeline_started", params: ["sessionId": id])
// ...после получения DesignPlan:
analytics.log(event: "design_pipeline_completed", params: [
    "sessionId": id,
    "durationMs": Int(Date().timeIntervalSince(startDate) * 1000),
    "provider": plan.providerName
])
```
Цель: P50 < 10 сек, P95 < 20 сек.

---

### 5.2 Risk Register

| # | Риск | Вероят. (1-5) | Влияние (1-5) | Score | Митигация | План отката |
|---|------|:---:|:---:|:---:|-----------|-------------|
| R1 | RoomPlan API изменится в iOS 19 | 2 | 5 | 10 | Абстрагировать за `RoomScanningProtocol`, следить за WWDC | Заморозить iOS 26 target на 3 мес |
| R2 | YandexGPT повышает цены / меняет API | 3 | 4 | 12 | Triplex fallback уже есть; мониторить changelog | Увеличить лимит GigaChat, CoreML |
| R3 | App Store реджект за использование камеры/LiDAR | 3 | 5 | 15 | Чёткое NSCameraUsageDescription, не хранить фото на сервере | Переработать Privacy section, реподать |
| R4 | Crashrate > 2% при LiDAR на старых устройствах | 4 | 4 | 16 | Тестирование iPhone 12/13/14 Pro, guard на RoomPlan availability | Скрыть LiDAR фичу на старых моделях |
| R5 | YDB недоступна → потеря истории дизайнов | 2 | 3 | 6 | LocalStorage как primary cache, YDB как sync | Работать офлайн, синхронизировать при восстановлении |
| R6 | Конкурент (Planner 5D, Homestyler) копирует фичу | 3 | 3 | 9 | Скорость + российский AI = дифференциатор | Ускорить роадмап B2B |
| R7 | GDPR/152-ФЗ: геометрия комнат = персональные данные? | 2 | 5 | 10 | Юр. консультация, Privacy Policy, геометрия не содержит лица | Локальное хранение только, opt-in для облака |
| R8 | Wildberries/Ozon закрывают affiliate API | 2 | 3 | 6 | Прямые ссылки через deeplink (не API) | Переключить на другой маркетплейс |

**Топ-3 риска по score:** R4 (16), R3 (15), R2 (12).

**Конкуренты — почему мы лучше:**
- Planner 5D: ручная расстановка, нет LiDAR, нет российского AI
- Homestyler: веб-ориентирован, нет AR walk-through, медленно
- Наш дифференциатор: **автоматический скан LiDAR → AI → AR за < 2 минут**, российские провайдеры (данные в РФ)

---

### 5.3 App Store Review Checklist

**Privacy — Info.plist ключи:**

```xml
<!-- Info.plist -->
<key>NSCameraUsageDescription</key>
<string>AIVibe использует камеру для сканирования комнаты с помощью технологии LiDAR. Никакие фотографии и видео не сохраняются и не отправляются на серверы.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Для сохранения рендеров вашего дизайна в галерею.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Для добавления изображений дизайна в вашу галерею.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Для улучшения точности AR-сцены в вашем пространстве.</string>

<!-- Если используем Sign in with Apple -->
<key>CFBundleURLTypes</key>
```

**RoomPlan — объяснение для Review:**
- В App Store Connect → App Privacy → данные комнаты: "Not Collected" (геометрия без фото)
- В описании приложения явно: "Мы сканируем геометрию вашей комнаты (размеры, форма), но не делаем фотографии"
- Privacy Policy: отдельная страница с объяснением что хранится локально

**Подписки (StoreKit 2):**

```swift
// Обязательные элементы UI:
// 1. Кнопка "Restore Purchases" на экране подписок
// 2. Ссылка на Terms of Service и Privacy Policy
// 3. Четкое описание что включено в каждый тариф
// 4. Информация о цене и периоде (до нажатия "Купить")
// 5. Отмена подписки: объяснить как (Настройки → Apple ID → Подписки)
```

**Что НЕЛЬЗЯ отправлять на сервер:**
- Фото и видео комнаты (только геометрия)
- Данные о расположении устройства
- Контакты, медиатека

**30-секундный демо-сценарий (по кадрам):**
```
0–5 сек:  Запуск приложения, главный экран
5–12 сек: Пользователь сканирует гостиную — видно как RoomPlan строит 3D модель в реальном времени
12–18 сек: Выбор стиля "Скандинавский", нажатие "Создать дизайн"
18–24 сек: AR-вид: мебель появляется в комнате, пользователь обходит сцену с телефоном
24–30 сек: Нажатие на диван → ссылка "Купить на Wildberries", логотип AIVibe
```

**Скриншоты (обязательные для App Store):**
1. Процесс LiDAR-сканирования (с 3D-сеткой)
2. Выбор стиля дизайна
3. AR-вид с мебелью в реальной комнате
4. Карточка дизайна с объяснением AI
5. Ссылки на покупку мебели

**Типичные причины реджекта AR-приложений:**
- ❌ Нет fallback для устройств без LiDAR → решение: `guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` + graceful degradation
- ❌ Приложение вылетает при отказе в разрешении камеры → решение: обработать `.denied` и показать объяснение
- ❌ Подписка оформляется без явного согласия → решение: confirmation alert перед покупкой

---

### 5.4 CI/CD Расширенный план

**Текущее:** SwiftLint → Build → Test (GitHub Actions, macOS-14)

**Расширение до production-grade:**

**`.github/workflows/ios.yml` — дополнения:**

```yaml
name: iOS CI/CD

on:
  push:
    branches: [master, main]
  pull_request:
    branches: [master, main]
  workflow_dispatch:
    inputs:
      deploy_target:
        description: 'testflight или appstore'
        required: false
        default: 'testflight'

env:
  SCHEME: "AIVibe"
  DESTINATION: "platform=iOS Simulator,name=iPhone 15 Pro,OS=18.0"
  RUBY_VERSION: "3.2"

jobs:
  swiftlint:
    name: SwiftLint
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: brew install swiftlint
      - run: swiftlint --strict

  build-and-test:
    name: Build + Test
    runs-on: macos-14
    needs: swiftlint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-spm-${{ hashFiles('**/Package.swift') }}
      - run: swift package resolve
      - run: |
          xcodebuild test \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -resultBundlePath TestResults \
            | xcpretty
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: test-results
          path: TestResults

  deploy-testflight:
    name: Deploy to TestFlight
    runs-on: macos-14
    needs: build-and-test
    if: github.ref == 'refs/heads/master' && github.event_name == 'push'
    environment: testflight
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ env.RUBY_VERSION }}
          bundler-cache: true
      - name: Deploy
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}                   # fedor@example.com
          APP_SPECIFIC_PASSWORD: ${{ secrets.APP_SPECIFIC_PASSWORD }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_URL: ${{ secrets.MATCH_GIT_URL }}
        run: bundle exec fastlane beta

  deploy-backend:
    name: Deploy Backend (Yandex Cloud)
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.ref == 'refs/heads/master'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install YC CLI
        run: |
          curl https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
          echo "$HOME/yandex-cloud/bin" >> $GITHUB_PATH
      - name: Deploy functions
        env:
          YC_TOKEN: ${{ secrets.YC_TOKEN }}          # IAM token
          YC_FOLDER_ID: ${{ secrets.YC_FOLDER_ID }}
        run: |
          yc config set token $YC_TOKEN
          yc config set folder-id $YC_FOLDER_ID
          # design-generate
          cd backend/functions/design-generate && npm ci
          yc serverless function version create \
            --function-name design-generate \
            --runtime nodejs20 \
            --entrypoint index.handler \
            --memory 512m \
            --execution-timeout 30s \
            --source-path .
          # design-refine (аналогично)
```

**`Fastlane/Fastfile` — шаблон:**

```ruby
# Fastlane/Fastfile
default_platform(:ios)

platform :ios do

  before_all do
    setup_ci if ENV['CI']
  end

  desc "Запустить тесты"
  lane :test do
    run_tests(
      scheme: "AIVibe",
      devices: ["iPhone 15 Pro"],
      clean: true
    )
  end

  desc "Собрать и загрузить в TestFlight"
  lane :beta do
    # Code signing через match (git-хранилище сертификатов)
    match(
      type: "appstore",
      git_url: ENV["MATCH_GIT_URL"],       # например: git@github.com:yourorg/certs.git
      app_identifier: "com.aivibe.app",    # ЗАМЕНИ на реальный bundle ID
      readonly: is_ci
    )

    # Инкремент build number (из количества коммитов)
    build_number = sh("git rev-list --count HEAD").strip
    increment_build_number(build_number: build_number)

    build_app(
      scheme: "AIVibe",
      configuration: "Release",
      export_method: "app-store"
    )

    upload_to_testflight(
      skip_waiting_for_build_processing: true,
      apple_id: ENV["APPLE_ID"],
      app_specific_password: ENV["APP_SPECIFIC_PASSWORD"]
    )
  end

  desc "Автоматические скриншоты (5 устройств)"
  lane :screenshots do
    capture_screenshots(
      scheme: "AIVibeUITests",
      devices: [
        "iPhone 15 Pro",
        "iPhone 15 Pro Max",
        "iPad Pro 12.9-inch (6th generation)"
      ],
      languages: ["ru-RU"]
    )
    frame_screenshots
    upload_to_app_store(skip_binary_upload: true)
  end

end
```

**`Fastlane/Matchfile`:**
```ruby
git_url(ENV["MATCH_GIT_URL"])   # ЗАМЕНИ: git-репозиторий для сертификатов
app_identifier(["com.aivibe.app"])
username(ENV["APPLE_ID"])
```

**Мониторинг после деплоя:**
- AppMetrica Dashboard: crash rate, DAU, воронка скан→дизайн→покупка
- Yandex Cloud Monitoring: latency Cloud Functions, error rate, cold starts
- GitHub Actions Slack-уведомление при провале: `appleboy/telegram-action`

**Canary deployment (бэкенд):**
```bash
# При деплое новой версии: сначала 10% трафика
yc serverless function version create --function-name design-generate --tag canary
# Через 30 минут если error rate < 1%:
yc serverless function version create --function-name design-generate --tag stable
```

---

### 5.5 План роста команды с Claude Code

#### Месяц 1 — Соло + Claude Code (80/20)

```
Распределение:
  Claude Code (80%): TCA Reducers, тесты, Node.js Cloud Functions, промпты
  Ты (20%): архитектурные решения, code review, интеграция на Mac, UX-решения

Правило: Claude Code НЕ принимает архитектурных решений — только реализует.
Каждый PR: ты читаешь diff и подтверждаешь перед merge.

Метрики эффективности Claude Code:
  - PR merge time цель: < 4 часов от задачи до merge
  - Bugs per 1K lines: цель < 2 (измерять через Crashlytics + тесты)
  - Test coverage: цель > 80%
```

#### Месяц 2 — Соло + Фрилансер UI + Claude Code

```
Распределение:
  Claude Code: TCA Reducers, тесты, рефакторинг, backend
  Фрилансер (UI/UX): SwiftUI views, анимации, дизайн-система
  Ты: интеграция Reducer↔View, code review обоих, деплой

Workflow:
  1. Ты создаёшь задачу (TCA State + Action → View)
  2. Claude Code пишет Reducer
  3. Фрилансер пишет View под готовый API
  4. Ты интегрируешь и тестируешь end-to-end
```

#### Месяц 3 — Команда 3 человека + Claude Code

**RACI-матрица:**

| Задача | Ты | Dev 2 | Dev 3 | Claude Code |
|--------|:--:|:-----:|:-----:|:-----------:|
| Архитектурные решения | A/R | C | C | C |
| TCA Reducers | A | R | — | R |
| SwiftUI Views | A | C | R | C |
| Unit-тесты | A | R | R | R |
| Backend Cloud Functions | A | — | R | R |
| Code Review | R | R | R | C |
| Промпт-инжиниринг | A | — | — | R |
| Деплой в TestFlight | A/R | — | — | — |
| Мониторинг / алерты | A/R | C | — | — |

A = Accountable, R = Responsible, C = Consulted

**Задачи которые ДЕЛЕГИРОВАТЬ Claude Code:**
- Любой шаблонный TCA Reducer по спецификации
- Unit-тесты по существующим сигнатурам
- Cloud Function по описанию API
- Рефакторинг: Sendable conformance, Swift 6 warnings
- Документирование публичного API

**Задачи которые НЕ ДЕЛЕГИРОВАТЬ Claude Code:**
- Финальные архитектурные решения (DI structure, module boundaries)
- App Store submission и review response
- Переговоры с партнёрами
- Решения о монетизации и ценообразовании
- UX-решения требующие пользовательского исследования

**Промт для Code Review через Claude Code:**
```
Ты — senior iOS developer, делаешь code review Pull Request для AIVibe.

КРИТЕРИИ РЕВЬЮ:
1. Swift 6 корректность: Sendable, actor-изоляция, нет data races
2. TCA паттерны: правильное использование Effect, Dependency, State
3. Тестируемость: все зависимости через протоколы
4. Производительность: нет блокирующих операций на MainActor
5. Безопасность: нет хардкода ключей, нет утечек приватных данных
6. Следование PROJECT_RULES_v2.md

DIFF для ревью:
[вставь git diff]

Дай:
- Список проблем с уровнем критичности (BLOCKER / WARNING / SUGGESTION)
- Конкретные правки для каждой проблемы
- Оценку: можно ли мержить (YES / NEEDS_CHANGES / NO)
```

**Job Description — AI-assisted iOS Developer:**
```
Мы ищем iOS-разработчика для AIVibe (дизайн интерьеров, AR, AI).

Стек: Swift 6, TCA, RoomPlan, RealityKit, Yandex Cloud
Особенность роли: активное использование Claude Code для генерации кода.
  - 50% времени: постановка задач для Claude, review результата
  - 50% времени: самостоятельная разработка сложных частей

Требования:
  - Swift 5+ (Swift 6 — плюс)
  - Понимание TCA или другой unidirectional архитектуры
  - Опыт с ARKit / RealityKit (плюс, не обязательно)
  - Умение работать с AI-инструментами, формулировать точные задачи
  - Английский — чтение документации
```

**Онбординг нового разработчика (неделя 1):**
```
День 1: Читает STRATEGY.md, PROJECT_RULES_v2.md, README.md
День 2: Делает PR "Hello World" — новый TCA Reducer с тестами (с помощью Claude Code)
День 3: Code review существующих файлов AIProviderRouter + CircuitBreaker
День 4: Самостоятельная задача: написать PromptBuilderTests с Claude Code как помощником
День 5: Ретро: что понял, что непонятно, план на следующую неделю
```

---

## 6. Следующие шаги (чеклист для тебя)

### Прямо сейчас — до первого промта в Claude Code

- [ ] **Получить доступ к Mac** (свой, арендованный, Mac Mini в облаке — MacStadium, AWS EC2 Mac)
- [ ] **Проверить что проект компилируется:** `swift build` в корне проекта
- [ ] **Запустить существующие тесты:** `swift test` — все 12 должны быть зелёными
- [ ] **Убедиться что Yandex Cloud работает:** есть IAM-токен, `echo $YANDEX_IAM_TOKEN` не пустой
- [ ] **Проверить GitHub Actions:** последний run должен быть зелёным
- [ ] **Открыть PROJECT_RULES_v2.md** — убедиться что все пути актуальны для твоей машины

### Данные для подготовки тестов

- [ ] **Mock CapturedRoom:** найти или создать тестовые данные CapturedRoom (можно записать на устройстве, сохранить как JSON)
- [ ] **Примеры ответов LLM:** собрать 5–10 примеров реальных ответов YandexGPT на промпт дизайнера
- [ ] **Тестовые комнаты:** иметь доступ к 2–3 комнатам разной формы для device-тестов

### Первый промт в Claude Code

**Скопируй промт из раздела W1/D1-2 (RoomGeometryExtractor) и отправь в Claude Code.**

Убедись что перед этим:
1. Xcode открыт с проектом AIVibe
2. Проект компилируется чисто
3. `AIVibe/Features/RoomScan/RoomScanFeature.swift` доступен для чтения

---

## 7. Вопросы к пользователю

> Ответь на эти вопросы — стратегия станет точнее.

### Технические
- [ ] Есть ли доступ к Mac для запуска Xcode прямо сейчас?
- [ ] Какие части уже протестированы на реальном iPhone с LiDAR?
- [ ] Yandex Cloud: IAM-токены настроены, Cloud Functions задеплоены?
- [ ] `swift build` проходит без ошибок?
- [ ] Что сейчас не компилируется или ломается?

### Продуктовые
- [ ] Целевая аудитория v1: обычные пользователи или дизайнеры-профессионалы?
- [ ] Нужен ли мультиязычный интерфейс или только русский?
- [ ] Есть ли уже потенциальные партнёры из мебельного ритейла?

### Ресурсные
- [ ] Команда: один разработчик или есть кто-то ещё?
- [ ] Бюджет на YandexGPT API (примерно сколько запросов в месяц планируется)?
- [ ] Есть ли жёсткий дедлайн (инвестор, конференция, партнёрский дедлайн)?

### Рыночные
- [ ] Только Россия или СНГ / международный рынок?
- [ ] Есть ли список дизайнеров, готовых войти в закрытую бету?
- [ ] Конкуренты, которых мониторишь?

---

## 8. Принятые решения

> Сюда записывай выборы по мере разработки.

| Дата | Решение | Альтернатива | Причина |
|------|---------|-------------|---------|
| 2026-05-18 | Оркестратор: Swift Actor (не LangGraph) | LangGraph, Hand-coded queues | Нет HTTP-overhead, нет сторонних сервисов, всё в Yandex Cloud |
| 2026-05-18 | AI-стек: YandexGPT → GigaChat → CoreML | OpenAI, Claude API | Данные остаются в РФ, российская аудитория |
| 2026-05-18 | Архитектура: TCA | MVVM, Redux | Предсказуемость состояния, тестируемость |

---

## 9. Открытые вопросы

> Вопросы на которые пока нет ответа.

- Как именно получить mock `CapturedRoom` для тестов без физического устройства?
- Поддерживает ли YandexGPT streaming SSE в текущей версии API?
- Нужна ли отдельная Apple Developer аккаунт для CI/CD match или можно использовать личный?
- Какой USDZ-каталог мебели использовать для MVP (готовый открытый или собирать вручную)?
- Как обрабатывать сканирование в помещениях с зеркалами (LiDAR артефакты)?
