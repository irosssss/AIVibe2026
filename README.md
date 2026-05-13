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
| Backend | Yandex Cloud Functions (Node.js 20) |
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

✅ Backend
   └── backend/                    (Yandex Cloud Function, Triplex fallback)

✅ Tests
   ├── MockAIProvider.swift        (Success, Failure, Counting моки)
   └── AIProviderRouterTests.swift (10 тестов на Swift Testing)

🔄 Features (ожидает Mac + Xcode)
   ├── RoomScan    (RoomPlan 2, LiDAR)
   ├── ARDesigner  (RealityKit 4)
   ├── AIAdvisor   (чат с AI)
   ├── Portfolio
   └── Marketplace
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
YANDEX_IAM_TOKEN       — IAM токен Yandex Cloud
YANDEX_FOLDER_ID       — ID папки в Yandex Cloud
GIGACHAT_CLIENT_SECRET — секрет клиента GigaChat
APP_TOKEN              — опциональный токен для проверки X-App-Token
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

Backend реализован как **Yandex Cloud Function** на Node.js 20.

Инструкция по деплою и настройке — в [`backend/README.md`](backend/README.md).

Основные эндпоинты:
- `POST /` — чат с AI (YandexGPT → GigaChat → Cache)
- Rate limit: 20 запросов/мин на userId
- Поддержка `imageBase64` для анализа изображений

---

## 📝 Разработка на Windows

Текущий этап (Core + Backend) разрабатывается на Windows через **Polza IDE** + DeepSeek V4 Flash.

Swift-код пишется и ревьюится в Polza IDE, компиляция и тесты выполняются через **GitHub Actions** на `macos-14` раннере.

Для Features (AR, RoomScan, UI) необходим Mac с Xcode 16+.

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
| 7 | Marketplace (требуется Mac) | ⏳ |
| 8 | Тестирование + TestFlight | ⏳ |

---

## 📄 Лицензия

© 2026 AIVibe. Все права защищены.
