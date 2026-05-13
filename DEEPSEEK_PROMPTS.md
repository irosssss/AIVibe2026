# AIVibe — Полная система промптов для DeepSeek V4 Flash
# Вставляй каждый промпт ОТДЕЛЬНО, дожидайся выполнения, затем следующий

---

## ═══════════════════════════════════════════
## СЕССИЯ 3 — YandexGPT Provider
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md @AIVibe/Core/AI/AIProvider.swift @AIVibe/Core/AI/AIModels.swift @AIVibe/Core/AI/AIError.swift

Создай файл AIVibe/Core/AI/Providers/YandexGPTProvider.swift

Требования:
- Реализует AIProviderProtocol, Sendable
- Endpoint: https://llm.api.cloud.yandex.net/foundationModels/v1/completion
- Auth: Bearer токен передаётся через init(iamToken: String, folderId: String)
- Модель: "gpt://\(folderId)/yandexgpt-5/latest"
- Timeout: 25 секунд через URLRequest.timeoutInterval
- При HTTP 429 → бросать AIError.rateLimitExceeded(provider: "YandexGPT", retryAfter: nil)
- При HTTP 200 → парсить JSON: choices[0].message.content → AIResponse
- var name: String = "YandexGPT"
- var isAvailable: Bool — делает HEAD запрос на endpoint, true если ответ < 500
- Swift 6, никаких force unwrap, все throws

Формат запроса к API:
{
  "modelUri": "gpt://folderId/yandexgpt-5/latest",
  "completionOptions": {"temperature": 0.7, "maxTokens": 1000},
  "messages": [{"role": "user", "text": "prompt"}]
}

Создай файл через терминал PowerShell командой New-Item + Set-Content
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 4 — GigaChat Provider
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md @AIVibe/Core/AI/AIProvider.swift @AIVibe/Core/AI/AIModels.swift @AIVibe/Core/AI/AIError.swift

Создай файл AIVibe/Core/AI/Providers/GigaChatProvider.swift

Требования:
- Реализует AIProviderProtocol, Sendable
- Auth endpoint: https://ngw.devices.sberbank.ru:9443/api/v2/oauth
- Chat endpoint: https://gigachat.devices.sberbank.ru/api/v1/chat/completions
- init(clientSecret: String) — clientSecret для OAuth
- Получать OAuth токен перед каждым запросом (или кэшировать на 29 минут)
- Модель: "GigaChat-Max"
- ВАЖНО: самоподписанный сертификат у GigaChat
  Добавь URLSessionDelegate реализацию с методом:
  urlSession(_:didReceive:completionHandler:) → .useCredential
  И большой комментарий: // ⚠️ ТОЛЬКО ДЛЯ РАЗРАБОТКИ. В продакшне использовать pinned certificate
- var name: String = "GigaChat"
- При ошибке OAuth → AIError.authenticationFailed
- Swift 6, actor для хранения токена

Создай файл через терминал
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 5 — CoreML Provider (оффлайн)
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md @AIVibe/Core/AI/AIProvider.swift @AIVibe/Core/AI/AIModels.swift @AIVibe/Core/AI/AIError.swift

Создай файл AIVibe/Core/AI/Providers/CoreMLProvider.swift

Требования:
- Реализует AIProviderProtocol, Sendable
- НЕ требует интернета — работает полностью оффлайн
- var name: String = "CoreML-Offline"
- var isAvailable: Bool = true (всегда доступен)

Для complete(prompt:):
  - Простой template matching по ключевым словам интерьера
  - Словарь ответов: ["диван" → "Для гостиной подойдёт угловой диван...", 
    "цвет" → "Для скандинавского стиля используйте белый, серый, бежевый...",
    "освещение" → "Многоуровневое освещение: основной свет + торшеры + точечные...",
    "стиль" → "Определите стиль: минимализм, скандинавский, лофт или классика..."]
  - Если ничего не найдено → базовый ответ об интерьере
  - AIResponse с isOffline: true, providerName: "CoreML-Offline"

Для analyzeImage(_:prompt:):
  - Заглушка с ответом об оффлайн режиме
  - AIResponse с isOffline: true

Добавь комментарий: // TODO: заменить на реальную CoreML модель когда будет .mlmodel файл

Создай файл через терминал
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 6 — NetworkClient
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md

Создай файл AIVibe/Core/Network/NetworkClient.swift

Требования:
- final class NetworkClient: Sendable
- Базируется на URLSession async/await (НЕ Alamofire)
- Методы:
  func get<T: Decodable>(url: URL, headers: [String: String]) async throws -> T
  func post<T: Decodable, B: Encodable>(url: URL, body: B, headers: [String: String]) async throws -> T
  func postRaw(url: URL, body: Data, headers: [String: String]) async throws -> Data
- Логирует каждый запрос через Logger (уже есть в Shared/Utils/Logger.swift)
- Обрабатывает HTTP статусы: 401→authenticationFailed, 429→rateLimitExceeded, 5xx→serverError
- JSONDecoder с .convertFromSnakeCase
- Timeout по умолчанию 30 секунд

Создай также NetworkError.swift рядом:
enum NetworkError: LocalizedError {
  case invalidURL
  case httpError(statusCode: Int, data: Data)
  case decodingFailed(Error)
  case timeout
  case noConnection
}

Создай оба файла через терминал
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 7 — AppMetrica Analytics Wrapper
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md

Создай файл AIVibe/Core/Analytics/AppMetricaAnalytics.swift

Требования:
- protocol AnalyticsProtocol — для тестируемости
  func track(event: AnalyticsEvent)
  func setUserProperty(_ value: String, forKey key: String)

- enum AnalyticsEvent с case-ами:
  aiRequestSent(provider: String)
  aiRequestSuccess(provider: String, latencyMs: Int)
  aiRequestFailed(provider: String, error: String)
  aiFallbackTriggered(from: String, to: String)
  roomScanStarted
  roomScanCompleted(area: Float)
  arObjectPlaced(objectType: String)
  marketplaceItemTapped(store: String, price: Int)
  portfolioItemViewed

- final class AppMetricaAnalytics: AnalyticsProtocol
  // Реальная реализация через AppMetrica SDK
  // Пока SDK не подключён — логировать через Logger
  // Добавь TODO: заменить Logger.log на AppMetrica.reportEvent(...)

- final class MockAnalytics: AnalyticsProtocol
  // Для тестов — просто печатает в консоль

Создай файл через терминал
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 8 — Тесты для AIProviderRouter
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md @AIVibe/Core/AI/AIProvider.swift @AIVibe/Core/AI/AIModels.swift @AIVibe/Core/AI/AIError.swift @AIVibe/Core/AI/AIProviderRouter.swift @AIVibe/Core/AI/CircuitBreaker.swift

Создай файл AIVibeTests/AI/AIProviderRouterTests.swift

Сначала создай MockAIProvider.swift в AIVibeTests/AI/:
- Реализует AIProviderProtocol
- init(name: String, shouldFail: Bool, failError: AIError = .providerUnavailable(provider: "Mock"))
- Считает количество вызовов: var callCount: Int

Тесты в AIProviderRouterTests:
1. test_primaryProviderSucceeds_noFallback()
   → первый провайдер успешен → второй не вызывается

2. test_primaryFails_fallsBackToSecondary()
   → первый падает → второй вызывается и возвращает ответ

3. test_allProvidersFail_throwsAllProvidersExhausted()
   → все три падают → ошибка .allProvidersExhausted

4. test_circuitBreakerOpen_providerSkipped()
   → CircuitBreaker открыт для первого → сразу идёт ко второму

5. test_circuitBreakerResetsAfterTimeout()
   → после 5 минут Circuit Breaker закрывается снова

Используй async/await тесты (Swift Testing или XCTest с async)
Создай оба файла через терминал
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 9 — Yandex Cloud Function (Backend)
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md @SESSION_04_backend.md

Создай папку backend/ в корне проекта со следующими файлами:

── backend/index.js ──
Yandex Cloud Function handler на Node.js 20
- exports.handler = async (event, context) => {}
- Парсит body: { prompt, userId, imageBase64? }
- Проверяет заголовок X-App-Token (простая валидация)
- Rate limit: Map userId → {count, resetTime} (in-memory, сбрасывается каждую минуту)
- Лимит: 20 запросов в минуту на userId
- Пробует YandexGPT → при ошибке → GigaChat → при ошибке → cached ответ
- Возвращает: { text, provider: "yandexgpt"|"gigachat"|"cache", latencyMs }
- Логирует каждый запрос в console.log (Yandex Cloud Logging подхватит)

── backend/yandexgpt.js ──
async function callYandexGPT(prompt, iamToken, folderId)
- fetch к https://llm.api.cloud.yandex.net/foundationModels/v1/completion
- timeout 20 секунд через AbortController
- возвращает строку с ответом или бросает Error

── backend/gigachat.js ──
async function getGigaChatToken(clientSecret)
async function callGigaChat(prompt, clientSecret)
- OAuth + chat completions
- process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0' для dev
- Комментарий: ⚠️ только для разработки

── backend/cache.js ──
Простой in-memory кэш последних 50 ответов
Map с ключом = первые 50 символов промпта
TTL = 1 час

── backend/package.json ──
{ "name": "aivibe-backend", "version": "1.0.0", 
  "dependencies": {}, "engines": { "node": "20" } }

── backend/README.md ──
Инструкция деплоя:
1. yc serverless function create --name aivibe-ai-advisor
2. Переменные окружения: YANDEX_IAM_TOKEN, YANDEX_FOLDER_ID, GIGACHAT_CLIENT_SECRET
3. yc serverless function version create --runtime nodejs20 ...

Создай все файлы через терминал
```

---

## ═══════════════════════════════════════════
## СЕССИЯ 10 — Обновление README и документации
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md @README.md

Перепиши README.md полностью. Исправь:

1. git clone URL → https://github.com/irosssss/AIVibe2026.git
2. © 2024 → © 2026
3. Добавь секцию "Текущее состояние проекта":
   ✅ Core/AI Layer (AIError, AIProvider, AIModels, CircuitBreaker, AIProviderRouter)
   ✅ AI Providers (YandexGPT, GigaChat, CoreML offline)
   ✅ Core/Network (NetworkClient)
   ✅ Core/Analytics (AppMetrica wrapper)
   ✅ Backend (Yandex Cloud Function)
   ✅ Tests (AIProviderRouterTests)
   🔄 Features (ожидает Mac + Xcode)
   
4. Добавь секцию "Разработка на Windows":
   Текущий этап (Core/Backend) разрабатывается на Windows через Polza IDE.
   Для Features (AR, RoomScan) необходим Mac с Xcode 16+.
   CI/CD через GitHub Actions macos-14 runner.

5. Убери упоминание CocoaPods — используем SPM

Перезапиши файл через терминал (Set-Content)
```

---

## ═══════════════════════════════════════════
## ФИНАЛЬНАЯ ПРОВЕРКА после всех сессий
## ═══════════════════════════════════════════

```
@PROJECT_RULES.md

Проверь структуру проекта командой в терминале:
Get-ChildItem -Recurse -Filter "*.swift" | Select-Object FullName

Убедись что есть:
□ AIVibe/Core/AI/AIError.swift
□ AIVibe/Core/AI/AIProvider.swift
□ AIVibe/Core/AI/AIModels.swift
□ AIVibe/Core/AI/CircuitBreaker.swift
□ AIVibe/Core/AI/AIProviderRouter.swift
□ AIVibe/Core/AI/Providers/YandexGPTProvider.swift
□ AIVibe/Core/AI/Providers/GigaChatProvider.swift
□ AIVibe/Core/AI/Providers/CoreMLProvider.swift
□ AIVibe/Core/Network/NetworkClient.swift
□ AIVibe/Core/Network/NetworkError.swift
□ AIVibe/Core/Analytics/AppMetricaAnalytics.swift
□ AIVibeTests/AI/MockAIProvider.swift
□ AIVibeTests/AI/AIProviderRouterTests.swift

Если каких-то файлов нет — создай их.
После — git add . && git commit -m "feat: complete Core layer - providers, network, analytics, tests" && git push origin master
```
