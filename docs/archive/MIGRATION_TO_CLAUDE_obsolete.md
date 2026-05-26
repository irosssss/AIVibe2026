# AIVibe — План миграции на Claude API

> Дата: 2026-05-25
> Статус: ЧЕРНОВИК — ничего не менялось, только анализ и пошаговый план.

---

## 1. Текущая архитектура (AS-IS)

### 1.1 AI-провайдеры (Triplex Fallback)

```
YandexGPT 5 Pro (основной)
    ↓ fallback
GigaChat-Max (резервный)
    ↓ fallback
CoreML / Cache (оффлайн)
```

**Где используется:**

| Слой | Файл | Провайдер | Назначение |
|------|-------|-----------|------------|
| iOS | `AIVibe/Core/AI/Providers/YandexGPTProvider.swift` | YandexGPT | Completion + Vision |
| iOS | `AIVibe/Core/AI/Providers/GigaChatProvider.swift` | GigaChat | Completion (OpenAI-совместимый) |
| iOS | `AIVibe/Core/AI/Providers/CoreMLProvider.swift` | CoreML (шаблоны) | Оффлайн fallback |
| iOS | `AIVibe/Core/AI/AIProviderRouter.swift` | Роутер | Triplex Fallback + Circuit Breaker |
| iOS | `AIVibe/App/DI/AppDependencies.swift` | DI | Сборка live-роутера |
| Backend | `backend/shared/yandexgpt.js` | YandexGPT | Completion + Embedding |
| Backend | `backend/shared/gigachat.js` | GigaChat | Completion (OAuth) |
| Backend | `backend/shared/triplex-fallback.js` | Роутер | YandexGPT → GigaChat → Cache |
| Backend | `backend/index.js` | Entry point | Main proxy handler |
| Backend | `backend/functions/ai-advisor/index.js` | Entry point | Advisor-функция |
| Backend | `backend/functions/marketplace/index.js` | YandexGPT | AI-обогащение товаров |
| Backend | `backend/functions/rag-indexer/index.js` | YandexGPT Embedding | Индексация RAG |

### 1.2 Секреты (env variables / Yandex Lockbox)

| Секрет | Где используется | Нужен после миграции? |
|--------|------------------|-----------------------|
| `YANDEX_IAM_TOKEN` | YandexGPT (iOS + Backend) | **НЕТ** → заменить на `ANTHROPIC_API_KEY` |
| `YANDEXGPT_FOLDER_ID` | YandexGPT (iOS + Backend) | **НЕТ** → убрать |
| `GIGACHAT_CLIENT_ID` | GigaChat (Backend) | **НЕТ** → убрать |
| `GIGACHAT_CLIENT_SECRET` | GigaChat (iOS + Backend) | **НЕТ** → убрать |
| `APP_TOKEN` | Auth (Backend) | ДА — оставить как есть |
| `APIFY_API_TOKEN` | Apify (Backend) | ДА — оставить как есть |

**Новые секреты:**

| Секрет | Назначение |
|--------|------------|
| `ANTHROPIC_API_KEY` | Claude API ключ |

### 1.3 Зависимости (SPM / npm)

#### iOS (Package.swift)

| Пакет | Версия | Связан с AI? | Действие |
|-------|--------|--------------|----------|
| swift-composable-architecture | 1.16+ | Нет (архитектура) | Оставить |
| Kingfisher | 7.12+ | Нет (изображения) | Оставить |
| swift-log | 1.5.4+ | Нет (логи) | Оставить |
| swift-collections | 1.1.4+ | Нет (структуры данных) | Оставить |

> **Нет iOS SDK от Anthropic.** Claude API — это REST API. Работа через `URLSession` (как сейчас YandexGPT). Никаких новых SPM-зависимостей не нужно.

#### Backend (package.json)

| Пакет | Связан с AI? | Действие |
|-------|--------------|----------|
| (нет зависимостей) | — | Добавить `@anthropic-ai/sdk` |

> Бэкенд-функции не имеют npm-зависимостей — все вызовы через `fetch`. Рекомендуется добавить `@anthropic-ai/sdk` для типизации и упрощения.

### 1.4 Circuit Breaker

Конфигурация синхронизирована между iOS и Backend:

| Параметр | Файл (iOS) | Файл (Backend) | Значение |
|----------|------------|-----------------|----------|
| Threshold | `CircuitBreakerConfig.swift` | `circuit-config.js` | 3 ошибки |
| Cooldown | `CircuitBreakerConfig.swift` | `circuit-config.js` | 5 минут |
| Providers | `CircuitBreaker.swift` | `circuit-config.js` | `['yandexgpt', 'gigachat']` |

**После миграции:** providers = `['claude']` (или `['claude', 'coreml']` если оставлять оффлайн).

### 1.5 Формат запросов/ответов

**Текущий формат (AIModels.swift):**

```swift
struct ChatMessage {
    let role: Role  // .system, .user, .assistant
    let content: String
}

struct AIPrompt {
    let messages: [ChatMessage]
    let temperature: Double      // 0.7
    let maxTokens: Int           // 1024
}

struct AIResponse {
    let text: String
    let providerName: String
    let isOffline: Bool
    let tokensUsed: Int
}
```

**Claude API формат:**

```json
{
    "model": "claude-sonnet-4-6",
    "max_tokens": 1024,
    "system": "Ты — AI-ассистент...",
    "messages": [
        {"role": "user", "content": "..."},
        {"role": "assistant", "content": "..."}
    ]
}
```

**Ключевые отличия:**
1. `system` — отдельное поле, НЕ в массиве `messages`
2. `role` — только `user` и `assistant` (нет `system` в messages)
3. Поле `content` может быть массивом для vision: `[{"type": "text", ...}, {"type": "image", ...}]`
4. Ответ: `response.content[0].text` (массив блоков, не строка)
5. Tool use — нативная поддержка (не парсинг JSON из текста)

---

## 2. Что нужно изменить (SCOPE)

### 2.1 iOS-приложение (Swift)

| # | Файл | Изменение | Сложность |
|---|------|-----------|-----------|
| 1 | `Core/AI/Providers/ClaudeProvider.swift` | **НОВЫЙ ФАЙЛ** — реализация `AIProviderProtocol` для Claude API | Средняя |
| 2 | `Core/AI/Providers/YandexGPTProvider.swift` | Удалить или оставить как legacy fallback | Низкая |
| 3 | `Core/AI/Providers/GigaChatProvider.swift` | Удалить или оставить как legacy fallback | Низкая |
| 4 | `Core/AI/AIModels.swift` | Обновить `ChatMessage.Role` — system выносится из messages | Средняя |
| 5 | `Core/AI/AIProviderRouter.swift` | Обновить providers list + breakers | Низкая |
| 6 | `App/DI/AppDependencies.swift` | Заменить `makeYandexGPT()` / `makeGigaChat()` на `makeClaude()` | Низкая |
| 7 | `Core/AI/Agent/AgentLoop.swift` | Обновить `generateModelOutput()` — использовать tool_use вместо JSON-парсинга | **Высокая** |
| 8 | `Core/AI/Agent/ContextBuilder.swift` | Вынести system prompt в отдельное поле (Claude API requirement) | Средняя |
| 9 | `Core/AI/CircuitBreakerConfig.swift` | Обновить список providers | Низкая |
| 10 | `Core/AI/Connectors/OzonConnector.swift` | Без изменений | — |
| 11 | `Core/AI/Connectors/WildberriesConnector.swift` | Без изменений | — |
| 12 | `Core/AI/Connectors/LockBoxSecretsManager.swift` | Добавить `ANTHROPIC_API_KEY` | Низкая |

### 2.2 Backend (Node.js)

| # | Файл | Изменение | Сложность |
|---|------|-----------|-----------|
| 1 | `shared/claude.js` | **НОВЫЙ ФАЙЛ** — клиент Claude API (`@anthropic-ai/sdk` или `fetch`) | Средняя |
| 2 | `shared/yandexgpt.js` | Удалить или оставить как fallback | Низкая |
| 3 | `shared/gigachat.js` | Удалить | Низкая |
| 4 | `shared/triplex-fallback.js` | Заменить YandexGPT → Claude, убрать GigaChat | Средняя |
| 5 | `shared/secrets.js` | Заменить YandexGPT/GigaChat секреты на `ANTHROPIC_API_KEY` | Низкая |
| 6 | `shared/circuit-config.js` | Обновить `CIRCUIT_PROVIDERS` → `['claude']` | Низкая |
| 7 | `shared/rag-search.js` | Embedding: YandexGPT → Claude / Voyager или оставить YandexGPT | Средняя |
| 8 | `functions/ai-advisor/index.js` | Без изменений (использует triplex-fallback) | — |
| 9 | `functions/marketplace/index.js` | Заменить `callYandexGPT` → `callClaude` | Низкая |
| 10 | `functions/rag-indexer/index.js` | Embedding: заменить `getEmbedding` | Средняя |
| 11 | `functions/image-gen/index.js` | Без изменений (использует Apify) | — |
| 12 | `index.js` | Без изменений (использует triplex-fallback) | — |
| 13 | `package.json` (backend) | Добавить `@anthropic-ai/sdk` | Низкая |

### 2.3 CI/CD

| # | Файл | Изменение |
|---|------|-----------|
| 1 | `.github/workflows/ios.yml` | Без изменений (build/test, не зависит от AI) |
| 2 | Yandex Cloud Lockbox | Добавить `ANTHROPIC_API_KEY`, убрать YandexGPT/GigaChat секреты |

### 2.4 Тесты

| # | Файл | Изменение |
|---|------|-----------|
| 1 | `AIVibeTests/AI/AIProviderRouterTests.swift` | Обновить моки под Claude | Средняя |
| 2 | `AIVibeTests/AI/AgentLoopTests.swift` | Обновить парсинг tool_use | Средняя |
| 3 | `AIVibeTests/AI/MockAIProvider.swift` | Оставить как есть (протокол не меняется) | — |
| 4 | `AIVibeTests/AI/Integration/AgentIntegrationTests.swift` | Обновить ожидаемые форматы | Средняя |

### 2.5 Что НЕ затрагивается

- `Core/AI/ToolRegistry/` — все инструменты (tools) остаются
- `Core/AI/Skills/` — скиллы остаются
- `Core/AI/Connectors/` — Ozon, Wildberries (REST API, не AI)
- `Features/` — все фичи (AIAdvisor, Marketplace, RoomScan, ARDesigner)
- `Core/Network/NetworkClient.swift` — HTTP-клиент (переиспользуется)
- `Core/Storage/StorageClient.swift` — хранение (не связано с AI)
- `Core/Analytics/AppMetricaAnalytics.swift` — аналитика (не связана с AI)
- `demo-design-mg/` — лендинг (React/Next.js)
- `admin/` — админ-панель
- `Fastlane/` — деплой iOS
- `scripts/` — скрипты

---

## 3. Пошаговый план миграции

### Фаза 0: Подготовка (не трогаем код)

- [ ] **0.1** Зарегистрировать Anthropic аккаунт, получить API ключ
- [ ] **0.2** Выбрать модель для продакшена:
  - `claude-sonnet-4-6` — баланс скорость/качество (рекомендуется)
  - `claude-haiku-4-5-20251001` — быстрый/дешёвый для RAG enrichment
  - `claude-opus-4-7` — максимальное качество (для сложных задач)
- [ ] **0.3** Проверить лимиты API (rate limits, token limits)
- [ ] **0.4** Добавить `ANTHROPIC_API_KEY` в Yandex Lockbox
- [ ] **0.5** Протестировать API ключ вручную через curl

### Фаза 1: Backend — Claude клиент (параллельно с текущим)

- [ ] **1.1** Создать `backend/shared/claude.js` — клиент Claude API
  - Endpoint: `https://api.anthropic.com/v1/messages`
  - Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `Content-Type: application/json`
  - Поддержка: messages, system prompt, vision (images), tool_use
- [ ] **1.2** Добавить `@anthropic-ai/sdk` в `backend/package.json` (опционально — можно через fetch)
- [ ] **1.3** Обновить `backend/shared/secrets.js`:
  - Добавить `ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY`
  - Оставить YandexGPT секреты (пока оба работают параллельно)
- [ ] **1.4** Обновить `backend/shared/triplex-fallback.js`:
  - Порядок: Claude → YandexGPT (fallback) → Cache
  - Или: Claude → Cache (без YandexGPT)
- [ ] **1.5** Обновить `backend/shared/circuit-config.js`:
  - `CIRCUIT_PROVIDERS = ['claude', 'yandexgpt']` (или `['claude']`)
- [ ] **1.6** Обновить `backend/functions/marketplace/index.js`:
  - Заменить `callYandexGPT` → `callClaude`
- [ ] **1.7** Тест: задеплоить в Yandex Cloud, проверить `/health`

### Фаза 2: Backend — Embeddings / RAG

> **Важно:** Claude API НЕ предоставляет embedding endpoint.
> Варианты:
> - **Вариант A:** Оставить YandexGPT Embeddings (только для RAG) — минимум изменений
> - **Вариант B:** Использовать Voyage AI (рекомендуется Anthropic)
> - **Вариант C:** Использовать OpenAI Embeddings

- [ ] **2.1** Принять решение по embedding-провайдеру
- [ ] **2.2** Если Вариант A: оставить `yandexgpt.js` только для `getEmbedding()`, удалить `callYandexGPT()`
- [ ] **2.3** Если Вариант B/C: создать `backend/shared/embeddings.js` с новым провайдером
- [ ] **2.4** Обновить `backend/functions/rag-indexer/index.js` — import нового embedding
- [ ] **2.5** Обновить `backend/shared/rag-search.js` — import нового embedding
- [ ] **2.6** Переиндексировать RAG (embedding dimensions могут отличаться!)
  - YandexGPT embedding: ~256 или 1024 dim
  - Voyage: 1024 dim
  - При смене провайдера — полный re-index таблицы `rag_chunks`

### Фаза 3: iOS — Claude Provider

- [ ] **3.1** Создать `AIVibe/Core/AI/Providers/ClaudeProvider.swift`:
  ```swift
  public final class ClaudeProvider: AIProviderProtocol, Sendable {
      let name = "Claude"
      // REST API: POST https://api.anthropic.com/v1/messages
      // Headers: x-api-key, anthropic-version, Content-Type
      // Body: { model, max_tokens, system, messages }
      // Response: { content: [{ type: "text", text: "..." }] }
  }
  ```
- [ ] **3.2** Реализовать `complete(prompt:)` — маппинг AIPrompt → Claude Messages API
  - Выделить `system` role из messages в отдельное поле
  - Маппинг `ChatMessage.Role.system` → строка в `system` параметре
  - Маппинг `ChatMessage.Role.user/.assistant` → массив `messages`
- [ ] **3.3** Реализовать `analyzeImage(_:prompt:)` — Vision через Claude
  - Claude поддерживает images inline в `content` как `{"type": "image", "source": {"type": "base64", ...}}`
- [ ] **3.4** Обновить `AIModels.swift` (при необходимости):
  - `AIPrompt` — добавить опциональное поле `systemPrompt: String?`
  - Или: оставить как есть, а маппинг делать внутри `ClaudeProvider`
- [ ] **3.5** Обновить `AppDependencies.swift`:
  ```swift
  private static func makeClaude() -> ClaudeProvider {
      let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
      return ClaudeProvider(apiKey: apiKey)
  }
  ```
- [ ] **3.6** Обновить `prepareLiveRouter()`:
  ```swift
  let providers: [any AIProviderProtocol] = [
      makeClaude(),       // основной
      CoreMLProvider()    // оффлайн fallback
  ]
  ```
- [ ] **3.7** Обновить `CircuitBreakerConfig.swift` — если список providers жёстко закодирован

### Фаза 4: iOS — Agent Loop (Tool Use)

> **Критическое изменение.** Сейчас AgentLoop парсит JSON из текста ответа.
> Claude API имеет нативный tool_use — tool calls возвращаются структурированно.

- [ ] **4.1** Обновить `AgentLoop.generateModelOutput()`:
  - Передавать tool definitions в Claude API как `tools` параметр
  - Парсить `response.content` на блоки `type: "text"` и `type: "tool_use"`
  - Маппить `tool_use` блоки → `ToolCallRequest`
- [ ] **4.2** Обновить `AgentLoop.parseModelOutput()`:
  - Убрать ручной парсинг JSON из текста
  - Использовать структурированный ответ Claude
- [ ] **4.3** Обновить `ContextBuilder.swift`:
  - System prompt → отдельное поле `system` в Claude API
  - Tool definitions → `tools` параметр Claude API
  - Секции TRUSTED/DATA → system prompt + messages
- [ ] **4.4** Обновить tool definitions → Claude tool format:
  ```json
  {
    "name": "search_marketplace_furniture",
    "description": "Поиск мебели на маркетплейсах",
    "input_schema": {
      "type": "object",
      "properties": { ... },
      "required": [ ... ]
    }
  }
  ```
- [ ] **4.5** Обновить ToolRegistry для генерации Claude-совместимых tool schemas

### Фаза 5: Тесты

- [ ] **5.1** Обновить `AIProviderRouterTests.swift` — добавить Claude mock
- [ ] **5.2** Обновить `AgentLoopTests.swift` — новый формат ModelOutput
- [ ] **5.3** Обновить `AgentIntegrationTests.swift` — e2e с mock Claude
- [ ] **5.4** Проверить, что `MockAIProvider` всё ещё валиден
- [ ] **5.5** Добавить тесты для ClaudeProvider (unit)
- [ ] **5.6** Ручное тестирование: полный цикл advisor → tool_use → ответ

### Фаза 6: Cleanup

- [ ] **6.1** Удалить `YandexGPTProvider.swift` (если не нужен fallback)
- [ ] **6.2** Удалить `GigaChatProvider.swift`
- [ ] **6.3** Удалить `backend/shared/gigachat.js`
- [ ] **6.4** Удалить `backend/shared/yandexgpt.js` (или оставить для embeddings)
- [ ] **6.5** Удалить секреты из Yandex Lockbox: `YANDEX_IAM_TOKEN`, `YANDEXGPT_FOLDER_ID`, `GIGACHAT_CLIENT_*`
- [ ] **6.6** Обновить `ContextBuilder` — убрать упоминания Triplex Fallback из system prompt
- [ ] **6.7** Обновить README.md

---

## 4. Критические точки и риски

### 4.1 Embedding (RAG)

**Проблема:** Claude API не имеет embedding endpoint. Текущий RAG (`rag-indexer`, `rag-search`) использует `getEmbedding()` из YandexGPT.

**Решение:**
- Оставить YandexGPT только для embedding (минимум изменений)
- Или мигрировать на Voyage AI / OpenAI embeddings (полный re-index)

### 4.2 System prompt

**Проблема:** Текущий `ChatMessage.Role.system` передаётся как обычное сообщение. Claude API требует system prompt как отдельный параметр.

**Решение:** Фильтровать messages с role=system, собирать в строку, передавать в `system` поле.

### 4.3 Tool Use vs JSON парсинг

**Проблема:** Текущий AgentLoop парсит tool calls из текста ответа (ищет JSON блоки). Claude имеет нативный tool_use.

**Решение:** Полная переработка `generateModelOutput()` и `parseModelOutput()`. Это самое большое изменение.

### 4.4 Самоподписанный сертификат GigaChat

**Проблема:** GigaChatProvider использует кастомный URLSessionDelegate для самоподписанного сертификата.

**Решение:** Claude API использует стандартный TLS — этот хак не нужен. Удалить.

### 4.5 OAuth (GigaChat)

**Проблема:** GigaChat использует OAuth 2.0 с кэшированием токена (30 мин TTL).

**Решение:** Claude API использует статический API ключ — значительно проще. Удалить весь OAuth flow.

### 4.6 Rate Limiting

**Текущий:** 20 req/min per userId (in-memory).
**Claude API:** Tier-зависимый (TPM/RPM). Проверить лимиты тарифа.

### 4.7 Стоимость

| Модель | Input (per 1M tokens) | Output (per 1M tokens) |
|--------|----------------------|------------------------|
| claude-sonnet-4-6 | $3 | $15 |
| claude-haiku-4-5 | $0.80 | $4 |
| claude-opus-4-7 | $15 | $75 |

> Рекомендация: Sonnet для основного потока, Haiku для RAG enrichment.

---

## 5. Маппинг API-форматов

### 5.1 Запрос: YandexGPT → Claude

**YandexGPT:**
```json
{
    "modelUri": "gpt://folder-id/yandexgpt-5/latest",
    "completionOptions": {
        "temperature": 0.7,
        "maxTokens": 2000
    },
    "messages": [
        {"role": "system", "text": "Ты ассистент..."},
        {"role": "user", "text": "Привет"}
    ]
}
```

**Claude:**
```json
{
    "model": "claude-sonnet-4-6",
    "max_tokens": 2000,
    "temperature": 0.7,
    "system": "Ты ассистент...",
    "messages": [
        {"role": "user", "content": "Привет"}
    ]
}
```

### 5.2 Ответ: YandexGPT → Claude

**YandexGPT:**
```json
{
    "result": {
        "alternatives": [{
            "message": {"role": "assistant", "text": "..."}
        }],
        "usage": {"inputTokens": 10, "completionTokens": 50}
    }
}
```

**Claude:**
```json
{
    "id": "msg_...",
    "type": "message",
    "role": "assistant",
    "content": [{"type": "text", "text": "..."}],
    "usage": {"input_tokens": 10, "output_tokens": 50}
}
```

### 5.3 Vision: YandexGPT → Claude

**YandexGPT (multimodal content):**
```json
{
    "messages": [{
        "role": "user",
        "content": [
            {"type": "text", "text": "Что на фото?"},
            {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
        ]
    }]
}
```

**Claude:**
```json
{
    "messages": [{
        "role": "user",
        "content": [
            {"type": "text", "text": "Что на фото?"},
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "..."}}
        ]
    }]
}
```

### 5.4 Tool Use (только Claude — замена JSON-парсинга)

**Claude запрос с tools:**
```json
{
    "model": "claude-sonnet-4-6",
    "max_tokens": 2000,
    "system": "...",
    "tools": [{
        "name": "search_marketplace_furniture",
        "description": "Поиск мебели на маркетплейсах Wildberries/Ozon",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Поисковый запрос"},
                "budget_max": {"type": "integer", "description": "Максимальный бюджет в рублях"}
            },
            "required": ["query"]
        }
    }],
    "messages": [{"role": "user", "content": "Найди диван до 50000"}]
}
```

**Claude ответ с tool_use:**
```json
{
    "content": [
        {"type": "text", "text": "Ищу подходящие варианты..."},
        {
            "type": "tool_use",
            "id": "toolu_01...",
            "name": "search_marketplace_furniture",
            "input": {"query": "диван", "budget_max": 50000}
        }
    ],
    "stop_reason": "tool_use"
}
```

---

## 6. Порядок действий (рекомендуемый)

```
Фаза 0  ─── Подготовка (1 день)
   │         API ключ, тест curl, Lockbox
   ▼
Фаза 1  ─── Backend Claude клиент (2-3 дня)
   │         claude.js, triplex обновление, marketplace
   │         Деплой → проверка /health
   ▼
Фаза 2  ─── Embeddings (1-2 дня)
   │         Решение по провайдеру, re-index (если нужен)
   ▼
Фаза 3  ─── iOS Provider (2-3 дня)
   │         ClaudeProvider.swift, DI, Router
   │         Базовая работа: complete + vision
   ▼
Фаза 4  ─── iOS Agent Loop (3-5 дней) ← САМОЕ СЛОЖНОЕ
   │         Tool Use, ContextBuilder, парсинг
   │         Полный цикл: запрос → tools → ответ
   ▼
Фаза 5  ─── Тесты (2-3 дня)
   │         Unit + integration + ручное тестирование
   ▼
Фаза 6  ─── Cleanup (1 день)
             Удаление YandexGPT/GigaChat, секреты, README
```

**Общая оценка: 12-17 рабочих дней**

---

## 7. Файлы без изменений (подтверждение)

Следующие файлы/директории **НЕ требуют изменений**:

```
AIVibe/Features/AIAdvisor/        — UI фичи (используют AIProviderRouter через DI)
AIVibe/Features/Marketplace/      — UI фичи
AIVibe/Features/RoomScan/         — LiDAR/AR
AIVibe/Features/ARDesigner/       — AR рендеринг
AIVibe/Core/Network/              — HTTP клиент (переиспользуется)
AIVibe/Core/Storage/              — Хранение данных
AIVibe/Core/Analytics/            — AppMetrica
AIVibe/Core/AI/ToolRegistry/      — Все tools (анализ, поиск, генерация, стиль)
AIVibe/Core/AI/Skills/            — Skill index + integration
AIVibe/Core/AI/Connectors/Ozon*   — Маркетплейс API
AIVibe/Core/AI/Connectors/Wb*     — Маркетплейс API
AIVibe/Core/AI/Connectors/Lock*   — Lockbox (только добавить ключ)
AIVibe/App/AppEntry.swift         — Entry point (без изменений)
backend/functions/image-gen/      — Apify (не AI provider)
backend/functions/ai-advisor/     — Использует triplex-fallback (изменится автоматически)
backend/index.js                  — Использует triplex-fallback (изменится автоматически)
backend/promptGuard.js            — Prompt injection guard (не зависит от провайдера)
backend/blockedUsers.js           — Модерация (не зависит от провайдера)
backend/shared/apify-client.js    — Apify (не AI)
backend/shared/ydb-client.js      — YDB (не AI)
demo-design-mg/                   — Лендинг (React)
admin/                            — Админ-панель
.github/workflows/ios.yml         — CI/CD (не зависит от AI)
Fastlane/                         — Деплой
scripts/                          — Утилиты
```
