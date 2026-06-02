# AIVibe

iOS-приложение для дизайна интерьеров с AR-расстановкой мебели и российским AI.

---

## 🚀 Что умеет AIVibe

- 📡 **LiDAR сканирование** — RoomPlan 2 создаёт точную 3D-модель комнаты
- 🤖 **Российский AI** — YandexGPT 5 анализирует интерьер, GigaChat как резерв, CoreML оффлайн
- 🪄 **AR дизайнер** — RealityKit + SpatialTracking, расставляй и двигай мебель через камеру
- 🛒 **Маркетплейсы РФ** — товары с Wildberries и Ozon через Apify
- 📵 **Оффлайн-режим** — Core ML работает без интернета
- 🤝 **Refine loop** — AI переставляет мебель по фидбеку пользователя

---

## 🛠️ Стек

| Слой | Технология |
|------|-----------|
| Платформа | iOS 26+, Swift 6.2 (approachable concurrency), Xcode 26.2+ |
| Архитектура | TCA (The Composable Architecture 1.25+) |
| AR | RoomPlan 2 + RealityKit + SpatialTrackingSession (iOS 26) |
| UI | SwiftUI |
| AI (основной) | YandexGPT 5 (`yandexgpt-5/latest`) |
| AI (резервный) | GigaChat-Max |
| AI (оффлайн) | Core ML (template matching) |
| Backend | Yandex Cloud Functions (Node.js 20 ESM) |
| Маркетплейсы | Apify actors (Wildberries, Ozon) |
| AI-поиск | RAG (YandexGPT embeddings + cosine similarity) |
| Аналитика | AppMetrica (wrapper) |
| CI/CD | GitHub Actions (`macos-26` runner) + SwiftLint --strict |
| Пакетный менеджер | SPM (swift-composable-architecture, Kingfisher, swift-log, swift-collections) |

---

## 📊 Текущее состояние (май 2026)

```
✅ Core/AI Layer
   ├── AIError.swift              (12 типов ошибок, LocalizedError + Sendable)
   ├── AIProvider.swift           (протокол AIProviderProtocol)
   ├── AIModels.swift             (AIPrompt, AIResponse, ChatMessage)
   ├── CircuitBreaker.swift       (actor, 3 ошибки → пауза 5 мин)
   ├── AIProviderRouter.swift     (actor, Triplex Fallback)
   ├── Agent/                     (AgentLoop max 8 шагов, AgentSession, ContextBuilder)
   ├── Skills/                    (design_advisor, furniture_matcher, budget_optimizer)
   ├── ToolRegistry/              (5 domain tools: AnalyzeRoom, SearchFurniture, ...)
   └── Providers/
       ├── YandexGPTProvider  ✅  (Yandex Cloud Foundation Models)
       ├── GigaChatProvider   ✅  (OAuth + самоподписанный сертификат)
       └── CoreMLProvider     ✅  (оффлайн, template matching)

✅ Core/Network + Core/Storage + Core/Analytics
   ├── NetworkClient.swift         (GET/POST/POSTRaw, async/await)
   └── AppMetricaAnalytics.swift   (AnalyticsProtocol + MockAnalytics)

✅ Backend (Yandex Cloud Functions, Node.js 20 ESM)
   ├── ai-advisor/              — Triplex fallback + rate limit + promptGuard + RAG
   ├── marketplace/             — Apify product search + YandexGPT enrich
   ├── rag-indexer/             — Ежедневная индексация дизайн-сайтов
   ├── image-gen/               — Генерация интерьеров через Apify
   └── shared/                  — yandexgpt, gigachat, apify-client, secrets, rag-search

✅ Features (TCA, все компилируются)
   ├── AIAdvisor/    — SwiftUI чат с AI, поддержка фото + стилей
   ├── Marketplace/  — MarketplaceFeature + MarketplaceView + backend Apify
   ├── RoomScan/     — RoomPlan 2 + LiDAR + AgentOrchestrator pipeline
   │                   (ScanAgent → AnalyzerAgent → DesignerAgent → CollisionDetector)
   └── ARDesigner/   — Полная RealityKit-реализация (Phase 4)
         ├── Domain/        FurnitureItem, RoomDesignPlan, CollisionTypes, ARSceneSnapshot
         ├── Assets/        USDZLoader (actor, 3-tier: сеть→bundle→placeholder, LRU 200MB)
         ├── Engine/        FurnitureEntityFactory (@MainActor), SceneDiffer (pure)
         ├── Services/      CollisionService + TCA DependencyKey
         ├── Feature/       ARSceneBridge (@MainActor @Observable, version-based apply)
         └── ARSceneBuilder — AnchorEntity(.plane), GroundingShadowComponent, incremental diff

✅ Tests  (72 тест-функции)
   ├── AIProviderRouterTests    (12 тестов, Swift Testing)
   ├── AgentLoopTests
   └── AgentIntegrationTests
```

---

## 🏗️ Архитектура AR-слоя (Phase 4)

AR Designer построен по 6-слойной архитектуре с однонаправленными зависимостями:

```
L1 Domain   — FurnitureItem, RoomDesignPlan, CollisionReport, ARSceneSnapshot
L2 Assets   — USDZLoader (actor) → USDZAsset (Sendable): сеть / bundle / placeholder
L3 Engine   — FurnitureEntityFactory (@MainActor), SceneDiffer (pure diff → SceneDelta)
L4 Services — CollisionDetector (Sendable struct), TCA DependencyKey
L5 Feature  — ARSceneBridge (@MainActor @Observable) + ARSceneBuilder (@MainActor)
L6 UI       — ARDesignerView (RealityView + жесты + coaching overlay)
```

**TCA-RealityKit bridge:**

```
ARDesignerFeature (TCA Reducer, Sendable)
       │  submit(items:geometry:selectedID:collisions:)
       ▼
ARSceneBridge — version++, applyTask?.cancel(), applyTask = Task { builder.apply(snapshot:) }
       │
       ▼
ARSceneBuilder — SceneDiffer.diff(old:new:) → [SceneOperation] → минимальные мутации Entity-дерева
       │
       ▼
RealityView — AnchorEntity(.plane(.horizontal, .floor))
                ├── floorPlane   (OcclusionMaterial, тени)
                ├── wallGroup    (debug, hidden by default)
                └── furnitureGroup
                      └── furniture_{uuid} (ModelEntity + GroundingShadowComponent
                                           + CollisionComponent + InputTargetComponent)
```

**Ключевые решения:**
- `ARSceneSnapshot.version: Int` — монотонный счётчик, устраняет race drag-end vs refine-complete
- `SceneDiffer` — pure function, избегает полного rebuild сцены при каждом изменении items
- `USDZAsset: Sendable` — `ModelEntity` никогда не пересекает actor boundary (Swift 6 чистота)
- `SpatialTrackingSession.run(Configuration(tracking: [.plane]))` — обязателен явно (iOS 26 не стартует автоматически)
- `GroundingShadowComponent` применяется рекурсивно ко всем `ModelEntity` в иерархии

---

## 🤖 AI Fallback схема

```
Запрос → YandexGPT 5 (yandexgpt-5/latest)
           ↓ (ошибка или timeout 25с)
         GigaChat-Max
           ↓ (ошибка или timeout 25с)
         Core ML (оффлайн, template matching)
           ↓ (ошибка)
         AIError.allProvidersExhausted
```

Circuit Breaker: после 3 ошибок подряд провайдер пропускается 5 минут.

---

## 🏁 Быстрый старт

### Требования

- **Xcode** 26.2+
- **Swift** 6.2
- **macOS** 15+ (для разработки)
- **Apple Developer Account** (для AR / TestFlight)
- **Yandex Cloud аккаунт** (для AI backend)

### Установка

```bash
git clone https://github.com/irosssss/AIVibe2026.git
cd AIVibe2026
swift package resolve
open AIVibe.xcodeproj
```

### Сборка и тесты

```bash
# Debug build
xcodebuild build -scheme AIVibe \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.3.1" \
  -configuration Debug -quiet

# Тесты
xcodebuild test -scheme AIVibe \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.3.1" -quiet

# Lint (строгий, как в CI)
swiftlint --strict
```

### Переменные окружения (backend)

Создай в Yandex Lockbox:

```
YANDEX_IAM_TOKEN           — IAM токен Yandex Cloud
YANDEX_FOLDER_ID           — ID папки в Yandex Cloud
GIGACHAT_CLIENT_SECRET     — секрет клиента GigaChat
GIGACHAT_CLIENT_ID         — ID клиента GigaChat
APIFY_API_TOKEN            — API токен Apify
APP_TOKEN                  — токен для проверки X-App-Token
```

---

## 🗄 Backend

Backend — набор **Yandex Cloud Functions** на Node.js 20 (ESM). Деплой и настройка — в [`backend/README.md`](backend/README.md).

### Функции

| Функция | Описание |
|---------|----------|
| `ai-advisor` | Triplex fallback (YandexGPT → GigaChat → CoreML) + RAG-контекст + promptGuard |
| `marketplace` | Поиск товаров через Apify + AI-объяснение |
| `rag-indexer` | Ежедневная индексация дизайн-сайтов в 03:00 МСК |
| `image-gen` | Генерация интерьеров через Apify Image Generation |

### Shared модули

| Модуль | Назначение |
|--------|-----------|
| `shared/yandexgpt.js` | YandexGPT: completion + getEmbedding |
| `shared/gigachat.js` | GigaChat: OAuth + completion |
| `shared/apify-client.js` | Apify: runActor (sync), startActor (async), getRunResults |
| `shared/rag-search.js` | Cosine similarity поиск по RAG-эмбеддингам |
| `shared/secrets.js` | Yandex Lockbox — управление секретами |
| `shared/triplex-fallback.js` | Triplex Fallback логика между провайдерами |

---

## 📅 Roadmap

| Фаза | Задача | Статус |
|------|--------|--------|
| 1 | Структура, CI/CD, Core/AI Router | ✅ |
| 2 | AI Providers (YandexGPT, GigaChat, CoreML) | ✅ |
| 3 | Backend (Yandex Cloud Functions) + AgentLoop + Skills | ✅ |
| 4 | Network Client + Analytics + тесты | ✅ |
| 5 | AIAdvisor + Marketplace + Apify + RAG | ✅ |
| 6 | RoomScan — RoomPlan 2 + AgentOrchestrator pipeline | ✅ |
| 7 | ARDesigner — Phase 4, полная RealityKit-миграция | ✅ |
| 8 | iOS 26 deployment target + Swift 6.2 approachable concurrency | ✅ |
| 9 | Security hardening — auth, promptGuard, prompt-injection защита (бэкенд + iOS) | ✅ |
| 10 | Локальное сохранение сессий — чат + проекты (Tier 2.1 / B1) | 🔄 PR #25 |
| — | Облачная синхронизация сессий (YDB, B2) | ⏳ |
| — | Auth (Sign in with Apple + Яндекс ID + VK ID) | ⏳ |
| — | Portfolio (публичные ссылки на AR-проекты) | ⏳ |
| — | AppMetrica SDK (сейчас wrapper) | ⏳ |
| — | TestFlight beta | ⏳ |

---

## 🔒 Безопасность

- **Никаких секретов в бандле** — все ключи через Yandex Lockbox / `LockBoxSecretsManager`
- **promptGuard.js** — обязательная проверка перед каждым AI-вызовом на backend
- **blockedUsers.js** — блокировка злоупотреблений
- **gitleaks** — сканирование секретов в CI (GitHub Actions)

---

## 📄 Лицензия

© 2026 AIVibe. Все права защищены.
