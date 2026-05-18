# AIVibe

iOS-приложение для дизайна интерьеров с AR и российским AI.

---

## 🚀 Что умеет AIVibe

- 📡 **LiDAR сканирование** — RoomPlan 2 создаёт точную 3D-модель комнаты
- 🤖 **Российский AI** — YandexGPT 5 анализирует интерьер, GigaChat как резерв, CoreML оффлайн
- 🪄 **AR дизайнер** — RealityKit 4, расставляй мебель через камеру
- 🛒 **Маркетплейсы РФ** — товары с Wildberries, Ozon, СберМегаМаркет
- 📵 **Оффлайн-режим** — Core ML работает без интернета
- 🗂 **Портфолио** — публичные ссылки на AR-проекты

---

## 🛠️ Стек

| Слой | Технология |
|------|-----------|
| Платформа | iOS 18+, Swift 6, Xcode 16 |
| Архитектура | TCA (The Composable Architecture) |
| AR | RoomPlan 2 + RealityKit 4 + LiDAR |
| AI (основной) | YandexGPT 5 Pro |
| AI (резервный) | GigaChat Ultra |
| AI (оффлайн) | Core ML Offline (template matching) |
| Backend | Yandex Cloud Functions (Node.js 20) — 4 функции + shared/ модули |
| Маркетплейсы | Apify API партнёров (Apify actors для Wildberries, Ozon) |
| AI-поиск | RAG (YandexGPT embeddings + cosine similarity) |
| AI-генерация | Apify Image Generation actor |
| Аналитика | AppMetrica (wrapper, SDK не подключён) |
| Auth | Sign in with Apple + Яндекс ID + VK ID |
| CI/CD | GitHub Actions + Fastlane |
| Пакетный менеджер | SPM (Swift Package Manager) |

---

## 📊 Текущее состояние проекта (июнь 2026)

```
✅ Core/AI Layer
   ├── AIError.swift              (12 типов ошибок)
   ├── AIProvider.swift           (протокол AIProviderProtocol)
   ├── AIModels.swift             (AIPrompt, AIResponse, ChatMessage)
   ├── CircuitBreaker.swift       (actor, 3 ошибки → пауза 5 мин)
   ├── AIProviderRouter.swift     (actor, Triplex fallback)
   └── Providers/
       ├── YandexGPTProvider  ✅  (Yandex Cloud Foundation Models)
       ├── GigaChatProvider   ✅  (OAuth + самоподписанный сертификат)
       └── CoreMLProvider     ✅  (оффлайн, template matching)

✅ Core/Network
   ├── NetworkClient.swift         (GET/POST/POSTRaw, async/await)
   └── NetworkError.swift          (invalidURL, httpError, decodingFailed, …)

✅ Core/Analytics
   └── AppMetricaAnalytics.swift   (AnalyticsProtocol + MockAnalytics)

✅ Backend (Yandex Cloud Functions, Node.js 20)
   ├── ai-advisor/              — Triplex fallback + rate limit + RAG
   ├── marketplace/             — Apify product search + YandexGPT enrich
   ├── rag-indexer/             — Ежедневная индексация дизайн-сайтов
   ├── image-gen/               — Генерация интерьеров через Apify
   └── shared/                  — apify-client, yandexgpt, gigachat, secrets, rag-search

✅ Swift Features (TCA, готово к компиляции на Mac)
   ├── AIAdvisor/    — DesignStyle, RoomType, DesignAdvice, AIAdvisorFeature
   ├── Marketplace/  — MarketplaceFeature + MarketplaceView + TCA Client
   └── ARDesigner/   — ImageGenClient (интеграция с DesignStyle/RoomType)

✅ Tests
   ├── MockAIProvider.swift        (Success, Failure, Counting моки)
   └── AIProviderRouterTests.swift (12 тестов на Swift Testing)

🔄 Ожидает Mac + Xcode
   ├── RoomScan    (RoomPlan 2, LiDAR)
   ├── Portfolio   (публичные ссылки)
   └── Auth        (Sign in with Apple + Яндекс ID + VK ID)
```

---

## 🏁 Быстрый старт

### Требования
- Xcode 16+
- Swift 6
- macOS 14+ (для разработки iOS-фич)
- Yandex Cloud аккаунт (для AI backend)

### Установка

```bash
git clone https://github.com/irosssss/AIVibe2026.git
cd AIVibe2026
swift package resolve
open AIVibe.xcodeproj
```

### Переменные окружения (backend)

Создай в Yandex Lockbox:
```
YANDEX_IAM_TOKEN           — IAM токен Yandex Cloud
YANDEX_FOLDER_ID           — ID папки в Yandex Cloud
GIGACHAT_CLIENT_SECRET     — секрет клиента GigaChat
GIGACHAT_CLIENT_ID         — ID клиента GigaChat
APIFY_API_TOKEN            — API токен Apify (для marketplace/image-gen)
APP_TOKEN                  — опциональный токен для проверки X-App-Token
```

### CI/CD

```bash
bundle exec fastlane test    # тесты
bundle exec fastlane beta    # TestFlight
```

---

## 🤖 AI Fallback схема

```
Запрос → YandexGPT 5 Pro
           ↓ (ошибка или timeout 25с)
         GigaChat Ultra
           ↓ (ошибка или timeout 25с)
         Core ML (оффлайн, template matching)
           ↓ (ошибка)
         AIError.allProvidersExhausted
```

Circuit Breaker: после 3 ошибок подряд провайдер пропускается 5 минут.

---

## 🗄 Backend

Backend реализован как набор **Yandex Cloud Functions** на Node.js 20.

Инструкция по деплою и настройке — в [`backend/README.md`](backend/README.md).

### Функции

| Функция | Описание | Файл |
|---------|----------|------|
| `ai-advisor` | Triplex fallback (YandexGPT → GigaChat → CoreML) + RAG-контекст | `backend/functions/ai-advisor/index.js` |
| `marketplace` | Поиск товаров через Apify + AI-объяснение | `backend/functions/marketplace/index.js` |
| `rag-indexer` | Ежедневная индексация дизайн-сайтов в 03:00 МСК | `backend/functions/rag-indexer/index.js` |
| `image-gen` | Генерация интерьеров через Apify Image Generation | `backend/functions/image-gen/index.js` |

### Shared модули

| Модуль | Назначение |
|--------|-----------|
| `shared/apify-client.js` | Apify API: runActor (sync), startActor (async), getRunResults |
| `shared/yandexgpt.js` | Обёртка YandexGPT: completion + getEmbedding |
| `shared/gigachat.js` | Обёртка GigaChat: OAuth + completion |
| `shared/rag-search.js` | Cosine similarity поиск по RAG-эмбеддингам |
| `shared/secrets.js` | Управление секретами через Yandex Lockbox |
| `shared/ydb-client.js` | ⚠️ Заглушка YDB (ожидает Yandex Database provisioning) |

---

## 📝 Разработка на Windows

Текущий этап (Core + Backend) разрабатывается на Windows через **Polza IDE** + DeepSeek V4 Flash.

Swift-код пишется и ревьюится в Polza IDE, компиляция и тесты выполняются через **GitHub Actions** на `macos-14` раннере.

Для Features (AR, RoomScan, UI) необходим Mac с Xcode 16+.

---

## 🍎 Что нужно для Mac (при переезде)

### Системные требования
- **macOS** 14 Sonoma или новее
- **Xcode** 16+
- **Swift** 6.0
- **Apple Developer Account** (для TestFlight / App Store)

### Шаги при первом запуске на Mac

```bash
# 1. Клонировать репозиторий
git clone https://github.com/irosssss/AIVibe2026.git
cd AIVibe2026

# 2. Запустить Xcode
open AIVibe.xcodeproj

# 3. Разрешить SPM (Xcode подтянет зависимости автоматически)
#    Пакеты: swift-composable-architecture, YandexMobileMetrica, etc.

# 4. Выбрать схему AIVibe → My Mac (или iOS Simulator 18+)
# 5. Cmd+B — собрать
# 6. Cmd+U — прогон тестов
```

### Что нужно дособрать на Mac (SES'и из DEEPSEEK_PROMPTS.md)

| Сессия | Фича | Статус |
|--------|------|--------|
| **СЕССИЯ 5 — AIAdvisor** | SwiftUI чат с AI (фото + стили) — код готов, ждёт компиляции | ✅ Код (TCA Reducer + DesignStyle/RoomType/DesignAdvice) |
| **СЕССИЯ 5 — RoomScan** | RoomPlan 2 + LiDAR | ⏳ Ожидает Mac + устройство с LiDAR |
| **СЕССИЯ 5 — ARDesigner** | RealityKit 4, расстановка мебели — ImageGenClient готов | ✅ ImageGenClient (TCA) + backend image-gen функция |
| **СЕССИЯ 5 — Portfolio** | Публичные ссылки на AR | ⏳ Ожидает Mac |
| **СЕССИЯ 7 — Marketplace** | Wildberries/Ozon через Apify — код готов | ✅ MarketplaceFeature + MarketplaceView + backend |
| **AppMetrica SDK** | Подключить реальный SDK (сейчас wrapper) | ⏳ После Xcode |
| **Auth** | Sign in with Apple + Яндекс ID + VK ID | ⏳ После Xcode |

### Чеклист при переезде

- [ ] `open AIVibe.xcodeproj` — проект открывается без ошибок
- [ ] `Cmd+B` — сборка успешна
- [ ] `Cmd+U` — все тесты проходят (AIProviderRouterTests, минимум 10)
- [ ] Подключить **AppMetrica SDK** через SPM
- [ ] Реализовать **AIAdvisor Feature** — `SESSION_05_ai_advisor.md`
- [ ] Реализовать **RoomScan** — `SESSION_05_room_scan.md`
- [ ] Настроить Fastlane для CI/CD на GitHub Actions
- [ ] Выкатить TestFlight beta

> 💡 **Совет:** начни с AIAdvisor — это чисто SwiftUI, не требует физического устройства.
> RoomScan и ARDesigner — только на реальном iPad/iPhone с LiDAR.

---

## 📅 Roadmap

| Неделя | Задача | Статус |
|--------|--------|--------|
| 1 | Структура, CI/CD | ✅ |
| 2 | Core/AI Router | ✅ |
| 2–3 | AI Providers (YandexGPT, GigaChat, CoreML) | ✅ |
| 3 | Backend (Yandex Cloud Function) | ✅ |
| 3 | Network Client + Analytics | ✅ |
| 3 | Тесты AIProviderRouter | ✅ |
| 4 | RoomScan (требуется Mac) | ⏳ |
| 5 | AR Designer (требуется Mac) | ⏳ |
| 6 | UI + Auth (требуется Mac) | ⏳ |
| 7 | Marketplace + ARDesigner ImageGen + RAG + Apify | ✅ |
| 8 | Тестирование + TestFlight | ⏳ |

---

## 📄 Лицензия

© 2026 AIVibe. Все права защищены.
