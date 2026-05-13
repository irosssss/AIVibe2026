# СЕССИЯ 2 — Russian AI Provider Router (Ядро системы)

> Добавь в контекст: @PROJECT_RULES.md
> Режим: Agent или обычный чат

---

Реализуй полный слой AIProviderRouter для AIVibe.
Это самый важный компонент — Triplex fallback между российскими AI.

## Компоненты для реализации

### 1. Протокол AIProvider
Файл: `Core/AI/AIProvider.swift`

```
protocol AIProvider: Sendable {
    var name: String { get }
    var isAvailable: Bool { get async }
    func complete(prompt: AIPrompt) async throws -> AIResponse
    func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse
}
```

### 2. YandexGPTProvider
Файл: `Core/AI/Providers/YandexGPTProvider.swift`

Требования:
- Endpoint: https://llm.api.cloud.yandex.net/foundationModels/v1/completion
- Auth: IAM-токен из Yandex Cloud (получать через backend, не хранить в app)
- Модели: yandexgpt-5 / yandexgpt-5-lite (lite как fallback внутри провайдера)
- Stream: поддержка SSE (Server-Sent Events) для стриминга
- Timeout: 30 секунд
- Retry: 2 попытки с exponential backoff

### 3. GigaChatProvider
Файл: `Core/AI/Providers/GigaChatProvider.swift`

Требования:
- Auth: OAuth через backend-прокси (никогда не в клиенте напрямую)
- Endpoint: https://gigachat.devices.sberbank.ru/api/v1/chat/completions
- Модели: GigaChat-Max → GigaChat-Pro (внутренний fallback)
- Важно: у GigaChat самоподписанный сертификат — обработай это

### 4. CoreMLProvider (оффлайн fallback)
Файл: `Core/AI/Providers/CoreMLProvider.swift`

Требования:
- Использует локальную Core ML модель (ONNX конвертированная)
- Только для базовых запросов (стиль интерьера, цвета)
- Явно помечает ответы как "Оффлайн-режим"
- Модель грузится lazy при первом обращении

### 5. AIProviderRouter (главный класс)
Файл: `Core/AI/AIProviderRouter.swift`

Логика Triplex Fallback:
```
Попытка 1: YandexGPT (основной)
    ↓ ошибка или timeout
Попытка 2: GigaChat (резервный)
    ↓ ошибка или timeout
Попытка 3: CoreML (оффлайн)
    ↓ ошибка
throw AIError.allProvidersExhausted
```

Дополнительно:
- Circuit Breaker паттерн: если провайдер упал 3 раза подряд —
  пропускать его 5 минут
- Логировать каждый fallback в AppMetrica
- Health check каждые 60 секунд (фоновый Task)

### 6. AIError
Файл: `Core/AI/AIError.swift`

```swift
enum AIError: LocalizedError {
    case networkUnavailable
    case providerUnavailable(provider: String)
    case rateLimitExceeded(provider: String, retryAfter: TimeInterval?)
    case invalidResponse(provider: String, details: String)
    case allProvidersExhausted
    case offlineModeActive
    case contentFiltered(reason: String) // российская цензура API
}
```

## Тесты
После кода напиши Unit-тесты:
- `AIProviderRouterTests.swift`
- Mock-провайдеры для каждого случая
- Тест fallback-цепочки
- Тест Circuit Breaker
- Тест при отсутствии сети

## Важно
- Весь код Swift 6, @Sendable везде где нужно
- Никаких API-ключей в коде — только через DI/Environment
- Укажи ссылку на документацию YandexGPT и GigaChat которую использовал
