# DeepSeek History — AIVibe Core Project

> Проект: AIVibe — iOS-приложение для дизайна интерьеров с AR и российским AI  
> Язык: Swift (iOS 17+) + TypeScript (React) + JavaScript (Node.js)  
> DeepSeek V4 Flash — хронология разработки

---

## 🧭 Протокол работы DeepSeek

1. **Перед любым изменением** — прочитай `DEEPSEEK_HISTORY.md` и `admin/admin-panel/DEEPSEEK_HISTORY.md`, чтобы знать состояние проекта.
2. **Не перечитывай все файлы заново** — история хранит, какие файлы уже изменены и какие шаги выполнены.
3. **После каждого завершённого действия** — обнови `DEEPSEEK_HISTORY.md` записью в таблицу соответствующего этапа.
4. **Формат записи**: `| Дата | Файл / Действие | Что сделано | Статус |`
5. **Статусы**: ✅ готово, 🔄 в процессе, ⏳ ожидание, ❌ ошибка.
6. **Если файл уже изменён в истории** — не меняй его снова, если не было новой команды.

---

## 📋 Обзор проекта

**AIVibe** — iOS-приложение для дизайна интерьеров. Пользователь фотографирует комнату → AI генерирует дизайн → AR показывает результат.

### Архитектура

```
┌──────────────────────┐     ┌──────────────────┐     ┌─────────────┐
│   AIVibe (iOS App)   │────→│   Backend        │────→│ YandexGPT   │
│   SwiftUI + TCA      │     │   Node.js        │     │ GigaChat    │
│   Swift 6           │     │   Cloud Function │     │ CoreML      │
└──────────────────────┘     └──────────────────┘     └─────────────┘
         │                          │
         ▼                          ▼
  AppMetrica Analytics        Yandex Cloud Logging
```

---

## 📜 Хронология работы DeepSeek

### Этап 1 — Инициализация проекта

| Дата | Действие | Статус |
|------|----------|--------|
| Июнь 2026 | Созданы корневые документы: `DEEPSEEK_PROMPTS.md`, `PROJECT_RULES_v2.md`, `SESSION_*` | ✅ |
| Июнь 2026 | Создан `Package.swift` (Swift Package Manager) | ✅ |
| Июнь 2026 | Создан `.swiftlint.yml` | ✅ |

### Этап 2 — AI Core Layer (Сессии 3–5)

| Дата | Файл | Описание | Сессия |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/AI/AIProvider.swift` | Протокол AI-провайдера | СЕССИЯ 2 |
| Июнь 2026 | `AIVibe/Core/AI/AIProviderRouter.swift` | Роутер + Circuit Breaker | СЕССИЯ 2 |
| Июнь 2026 | `AIVibe/Core/AI/AIProviderHelpers.swift` | Хелперы | СЕССИЯ 2 |
| Июнь 2026 | `AIVibe/Core/AI/AIModels.swift` | Модели данных | СЕССИЯ 2 |
| Июнь 2026 | `AIVibe/Core/AI/AIError.swift` | Типы ошибок | СЕССИЯ 2 |
| Июнь 2026 | `AIVibe/Core/AI/CircuitBreaker.swift` | Circuit Breaker | СЕССИЯ 2 |
| Июнь 2026 | `AIVibe/Core/AI/Providers/YandexGPTProvider.swift` | YandexGPT (модель yandexgpt-5/latest) | СЕССИЯ 3 |
| Июнь 2026 | `AIVibe/Core/AI/Providers/GigaChatProvider.swift` | GigaChat (модель GigaChat-Max) | СЕССИЯ 4 |
| Июнь 2026 | `AIVibe/Core/AI/Providers/CoreMLProvider.swift` | CoreML (on-device fallback) | СЕССИЯ 5 |

### Этап 3 — Network & Analytics (Сессии 6–7)

| Дата | Файл | Описание | Сессия |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/Network/NetworkClient.swift` | HTTP клиент (URLSession) | СЕССИЯ 6 |
| Июнь 2026 | `AIVibe/Core/Network/NetworkError.swift` | Типы сетевых ошибок | СЕССИЯ 6 |
| Июнь 2026 | `AIVibe/Core/Analytics/AppMetricaAnalytics.swift` | Yandex AppMetrica | СЕССИЯ 7 |

### Этап 4 — Tests (Сессия 8)

| Дата | Файл | Описание | Сессия |
|------|------|----------|--------|
| Июнь 2026 | `AIVibeTests/AI/MockAIProvider.swift` | Mock для тестов | СЕССИЯ 8 |
| Июнь 2026 | `AIVibeTests/AI/AIProviderRouterTests.swift` | Тесты роутера | СЕССИЯ 8 |

### Этап 5 — Backend (Сессия 9)

| Дата | Файл | Описание | Сессия |
|------|------|----------|--------|
| Июнь 2026 | `backend/index.js` | Yandex Cloud Function entry point | СЕССИЯ 9 |
| Июнь 2026 | `backend/yandexgpt.js` | Прокси для YandexGPT API | СЕССИЯ 9 |
| Июнь 2026 | `backend/gigachat.js` | Прокси для GigaChat API | СЕССИЯ 9 |
| Июнь 2026 | `backend/cache.js` | Кэширование ответов | СЕССИЯ 9 |
| Июнь 2026 | `backend/package.json` | Зависимости backend | СЕССИЯ 9 |
| Июнь 2026 | `backend/README.md` | Документация backend | СЕССИЯ 9 |

### Этап 6 — Admin Panel (TailAdmin React)

| Дата | Действие | Статус |
|------|----------|--------|
| Июнь 2026 | Клонирован TailAdmin React v2.3.0 | ✅ |
| Июнь 2026 | Установлены зависимости (`npm install`) | ✅ |
| Июнь 2026 | Создан `admin/admin-panel/DEEPSEEK_HISTORY.md` | ✅ |
| Июнь 2026 | Создан `admin/admin-panel/LAZYWEB_GUIDE.md` — Lazyweb MCP установка | ✅ |
| Июнь 2026 | Сохранён Lazyweb токен в `~/.lazyweb/lazyweb_mcp_token` | ✅ |

### Этап 7 — Prompt Injection Safety System

| Дата | Действие | Этап | Статус |
|------|----------|------|--------|
| Июнь 2026 | Hotfix: обязательный App Token, валидация входных данных (prompt ≤ 10k, userId ≤ 64, imageBase64 ≤ 5MB), atomic rate limiter, log sanitization | 0 | ✅ |
| Июнь 2026 | Создан `backend/promptGuard.js` — 3 уровня детекции инъекций (30+ regex, эвристики, скоринг severity 1–5) | 1 | ✅ |
| Июнь 2026 | Создан `backend/blockedUsers.js` — persistent JSON-хранилище, strikes → 24h ban, auto-cleanup | 2 | ✅ |
| Июнь 2026 | Интеграция в `backend/index.js`: path-based routing, admin API endpoints, guard pipeline, CORS для DELETE | 3 | ✅ |
| Июнь 2026 | Создана страница `BlockedUsersPage.tsx` + `blockedUsersApi.ts` — таблица, статистика, разблокировка | 4 | ✅ |
| Июнь 2026 | Исправление React 19 TS ошибок — 17 файлов: убран `React.FC`, замена на type-only пропсы | — | ✅ |

### Архитектура безопасности

```
Пользователь → POST /api/analyze
  ├─ 1. Валидация App Token
  ├─ 2. Валидация входных данных (prompt/userId/imageBase64)
  ├─ 3. Rate Limiter (20/min, atomic)
  ├─ 4. Проверка блокировки (blockedUsers.isBlocked)
  ├─ 5. Prompt Guard (severity ≥ 3 → strike + ban 24h)
  └─ 6. Triplex Fallback → ответ

Admin API endpoints:
  GET    /api/blocked-users          — список заблокированных
  GET    /api/blocked-users/stats    — статистика блокировок
  DELETE /api/blocked-users/:userId  — разблокировать
```

### ⏳ Ожидают Mac + Xcode

| Компонент | Причина | Статус |
|-----------|--------|--------|
| `Features/AIAdvisor/` (SwiftUI чат + TCA) | Требует SwiftUI / Xcode 16 | ⏳ Ждёт Mac |
| `Features/RoomScan/` (AR) | Требует RealityKit / Xcode | ⏳ Ждёт Mac |
| Сборка `.app` + тесты на симуляторе | Требует Xcode | ⏳ Ждёт Mac |

---

## ✅ Итог: Core Layer — готов

```
AIVibe/
├── AIVibe/Core/
│   ├── AI/          → 7 файлов (protocol, router, circuit breaker, 3 provider, models, errors, helpers) ✅
│   ├── Network/     → 2 файла (client, errors) ✅
│   ├── Analytics/   → 1 файл (AppMetrica + AnalyticsLogging) ✅
│   └── Storage/     → 1 файл (StorageClient) ✅
├── AIVibe/Features/
│   ├── AIAdvisor/   → ⏳ Ждёт Mac (SwiftUI chat + TCA)
│   └── RoomScan/    → 🟡 Наброски есть, требуется Mac для RealityKit
├── AIVibe/App/DI/   → AppDependencies.swift ✅ (исправлен под реальные типы)
├── AIVibeTests/
│   └── AI/          → 2 файла (mock, router tests) ✅
├── backend/         → 6 файлов (entry, 2 proxies, cache, package, readme) ✅
└── admin/admin-panel/ → TailAdmin React, готов к доработкам ✅
```

---

## 📎 Полезные ссылки

- [DEEPSEEK_PROMPTS.md](./DEEPSEEK_PROMPTS.md) — все задания DeepSeek по сессиям
- [PROJECT_RULES_v2.md](./PROJECT_RULES_v2.md) — правила проекта
- [backend/README.md](./backend/README.md) — документация backend
- [admin/admin-panel/DEEPSEEK_HISTORY.md](./admin/admin-panel/DEEPSEEK_HISTORY.md) — история админ-панели

---

### Этап 8 — ESM-конвертация backend (Шаг 2)

| Дата | Файл | Изменения | Статус |
|------|------|-----------|--------|
| Июнь 2026 | `backend/index.js` | `require('./...')` → `import { ... } from './....js'`; сигнатуры → `* as cache`; `module.exports.handler` → `export const handler` | ✅ |
| Июнь 2026 | `backend/cache.js` | `module.exports = { ... }` → `export { ... }` | ✅ |
| Июнь 2026 | `backend/blockedUsers.js` | `require('fs')`/`require('path')` → `import fs`/`import path` + `fileURLToPath` → `__filename`/`__dirname`; `module.exports = {` → `export {` | ✅ |
| Июнь 2026 | `backend/promptGuard.js` | `module.exports = {` → `export {`; удалён лишний `'use strict';` (ESM) | ✅ |
| Июнь 2026 | **Аудит + исправления** | `backend/index.js`: пути импорта `./yandexgpt.js` → `./shared/yandexgpt.js`; сигнатуры вызовов → объектный формат `callYandexGPT({prompt, ...})`; удалён дубль `backend/ai-advisor/` (оставлен `backend/functions/ai-advisor/`) | ✅ |

---

## 📎 Полезные ссылки

- [DEEPSEEK_PROMPTS.md](./DEEPSEEK_PROMPTS.md) — все задания DeepSeek по сессиям
- [PROJECT_RULES_v2.md](./PROJECT_RULES_v2.md) — правила проекта
- [backend/README.md](./backend/README.md) — документация backend
- [admin/admin-panel/DEEPSEEK_HISTORY.md](./admin/admin-panel/DEEPSEEK_HISTORY.md) — история админ-панели

---

### Этап 9 — Tool Registry (MVP Agent Blueprint §6)

| Дата | Файл | Описание | Статус |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ToolDefinitions.swift` | Базовые типы: RiskClass, PermissionDecision, ToolError, ToolResult, AgentTool протокол, ToolInputSchema, ToolCallRequest | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/PermissionEngine.swift` | Permission Matrix Evaluator: allow/deny/approvalRequired/sandbox. SessionContext, UserRole, CustomPermissionRule | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ResultLimiter.swift` | ResultLimiter (max 8000 символов) + ResultTrimmer (сжатие старых результатов до 12000 суммарно) | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ToolScheduler.swift` | Планировщик: группировка по risk priority, разрешение зависимостей, параллельные/последовательные группы | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ToolRegistry.swift` | Центральный actor: регистрация, поиск, validate → permission → execute с таймаутом → limit. TCA Dependency | ✅ |

### Сводка Tool Registry

```text
5 файлов, ~1500 строк Swift 6.

Компоненты:
  ToolRegistry (actor)         — центральный реестр, TCA Dependency
  PermissionEngine (actor)     — permission matrix evaluator
  ResultLimiter                — ограничение результата ≤ 8000 символов
  ResultTrimmer                — сжатие старых результатов ≤ 12000 суммарно
  ToolScheduler                — упорядочивание по risk priority + зависимости
  AgentTool (protocol)         — протокол инструмента
  ToolRiskClass (6 классов)    — readPublic, readPrivate, draft, action, financial, meta
  PermissionDecision (4 решения) — allow, deny, approvalRequired, sandbox
  ToolError (7 case-ов)        — toolNotFound, validationFailed, permissionDenied, ...
  ToolResult                   — унифицированный результат
  ToolCallRequest              — запрос на вызов (из model output)

Permission matrix (BluePrint §12):
  readPublic/readPrivate → allow
  draft                  → allow
  action                 → approval-gated
  financial              → DENY (MVP v1)
  internalState/meta     → allow

Следующий шаг: domain-specific инструменты (analyze_room_scan, search_marketplace_furniture, recommend_style, generate_arrangement_plan, draft_shopping_list)
```

### Итоговая структура Core/AI

```
AIVibe/Core/AI/
├── AIError.swift            ✅ (12 case-ов)
├── AIProvider.swift         ✅ (протокол)
├── AIModels.swift           ✅ (ChatMessage, AIPrompt, AIResponse)
├── AIProviderHelpers.swift  ✅
├── AIProviderRouter.swift   ✅ (actor, Triplex fallback, TCA Dependency)
├── CircuitBreaker.swift     ✅ (actor)
├── CircuitBreakerConfig.swift ✅
├── Providers/
│   ├── YandexGPTProvider.swift ✅
│   ├── GigaChatProvider.swift  ✅
│   └── CoreMLProvider.swift    ✅
└── ToolRegistry/
    ├── ToolDefinitions.swift   ✅ (типы, протокол)
    ├── PermissionEngine.swift  ✅ (permission matrix)
    ├── ResultLimiter.swift     ✅ (лимиты + trimmer)
    ├── ToolScheduler.swift     ✅ (планировщик)
    ├── ToolRegistry.swift      ✅ (центральный actor, +registerDomainTools())
    └── Tools/
        ├── AnalyzeRoomScanTool.swift        ✅ (Stage 2.1)
        └── SearchMarketplaceFurnitureTool.swift ✅ (Stage 2.2)
```

---

### Этап 10 — Domain Tools Stage 2 (MVP Agent Blueprint §6)

| Дата | Файл | Описание | Статус |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/Tools/AnalyzeRoomScanTool.swift` | Stage 2.1: Анализ LiDAR USDZ скана — RoomDimensions, DetectedObject, LightSource, RoomAnalysis.toJSON(). readPrivate, timeout 15s, maxResultChars 4000. mockAnalysis для Windows | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/Tools/SearchMarketplaceFurnitureTool.swift` | Stage 2.2: Поиск мебели Wildberries/Ozon — FurnitureSearchResult, FurnitureSearchResponse. 6 категорий, 5 стилей, фильтр по бюджету. readPublic, timeout 10s, maxResults 20. mockSearch для Windows | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ToolRegistry.swift` | Добавлен `registerDomainTools()` — регистрирует AnalyzeRoomScanTool + SearchMarketplaceFurnitureTool. Preview использует реальные инструменты вместо моков | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/Tools/RecommendStyleTool.swift` | Stage 2.3: Рекомендация стиля интерьера — StyleRecommendation, StyleProfile (5 стилей + traits), RoomConstraints (освещение/форма/функция), ColorPalette. draft, timeout 20s, maxResultChars 3000. mockRecommend для Windows. Зарегистрирован в ToolRegistry.registerDomainTools() (3/5) | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/Tools/GenerateArrangementTool.swift` | Stage 2.4: План расстановки мебели с AR-координатами — FurniturePlacement (position/rotation/scale), ArrangementPlan (placements, walkPathScore, visualBalanceScore, warnings, freeFloorAreaM2). Collision detection, forbidden zones (окна/двери/батареи), эвристики по категориям (sofa → вдоль стен, table → центр, chair → периметр). draft, timeout 15s, maxItems 30. Зарегистрирован в ToolRegistry.registerDomainTools() (4/5) | ✅ |

| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/Tools/DraftShoppingListTool.swift` | Stage 2.5: Список покупок — ShoppingListItem (name/url/price/marketplace/quantity/furnitureId/category), ShoppingListResponse (totalPriceRub/budgetRemaining/budgetWarning/optimizationTips). BudgetWarning (overBudget/underutilized/tight/ok). DraftShoppingListInput.Selection. draft, timeout 5s, maxResultChars 4000. deterministicPrice/deterministicName/deterministicCategory для mock. previewList() для preview. Зарегистрирован в ToolRegistry.registerDomainTools() (5/5) | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ToolRegistry.swift` | registerDomainTools() → 5/5 (DraftShoppingListTool добавлен) | ✅ |

### Сводка Stage 2 Progress

```text
Domain Tools: 5/5 ГОТОВО 🎉

✅ analyze_room_scan           — LiDAR USDZ анализ (420 строк)
✅ search_marketplace_furniture — WB/Ozon поиск (380 строк)
✅ recommend_style             — рекомендация стиля (520 строк)
✅ generate_arrangement_plan   — план расстановки (680 строк)
✅ draft_shopping_list         — список покупок (450 строк)
```

### Итог Tool Registry — полностью готов

```
AIVibe/Core/AI/ToolRegistry/                    ← 10 файлов, ~3500 строк Swift 6
├── ToolDefinitions.swift                       ← базовые типы
├── PermissionEngine.swift                      ← permission matrix
├── ResultLimiter.swift                         ← лимиты + trimmer
├── ToolScheduler.swift                         ← планировщик
├── ToolRegistry.swift                          ← центральный actor (TCA Dependency)
└── Tools/
    ├── AnalyzeRoomScanTool.swift               ← Stage 2.1
    ├── SearchMarketplaceFurnitureTool.swift     ← Stage 2.2
    ├── RecommendStyleTool.swift                ← Stage 2.3
    ├── GenerateArrangementTool.swift           ← Stage 2.4
    └── DraftShoppingListTool.swift             ← Stage 2.5
```

**Blueprint §6 coverage — 100%:**
```
analyze_room_scan ✅    search_marketplace_furniture ✅
recommend_style ✅      generate_arrangement_plan ✅
draft_shopping_list ✅ (confirm_purchase_order — DENY в MVP)
```

**Следующий этап:** Core Agentic Loop (Blueprint §4) — run_aivibe_agent, context builder, Triplex Fallback в loop, auto-compaction.

---

---

### Этап 11 — Core Agentic Loop (Blueprint §4, §5, §7, §8, §9)

| Дата | Файл | Описание | Статус |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/AI/Agent/AgentSession.swift` | Session state: AgentSession actor — события, планы, goal state, todo, approval records, skills, connectors, artifacts, compaction summaries, provider health. SessionEvent (10 типов), DesignPlan (Plan Artifact), GoalState (checkpoints + progress), TodoItem, ApprovalRecord, ConnectorStatus, SessionArtifact, CompactionSummary, ProviderHealth. Blueprint §9 | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/Agent/ContextBuilder.swift` | Context Builder: 11 секций (trust boundary) — system instructions → harness policy → domain policy → active plan → skill index → tool definitions → LiDAR scan data → marketplace data → style guides → tool observations → user request. AgentContext, ContextSection (trusted/data). SkillIndex (3 skills: design_advisor, furniture_matcher, budget_optimizer). Blueprint §5, §10 | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/Agent/AgentLoop.swift` | Core Agentic Loop: run() — главный цикл (maxSteps=8), generateModelOutput (Triplex Fallback), parseModelOutput (JSON/Markdown/plain text). runGoalLoop() — long-running задачи с checkpoints. shouldActivatePlanningMode() — активация planning mode (бюджет >500k, комната >30м², нет стиля, vague запросы). SessionCompactor — auto-compaction при 80% заполнении контекста. AgentLoopResult (5 case-ов), UserRequest (3 input types). RoomAnalysis placeholder. Blueprint §4, §7, §8 | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/ToolRegistry/ToolRegistry.swift` | Добавлен AgentLoop TCA Dependency (liveValue/testValue/previewValue — все с registerDomainTools). Blueprint §4 | ✅ |

### Сводка Stage 3

```text
3 файла, ~65KB Swift 6.

AgentLoop (actor)                    — главный цикл агента
├── run(request, session)           — основной цикл (до 8 шагов)
├── generateModelOutput()           — Triplex Fallback (YandexGPT → GigaChat → CoreML)
├── parseModelOutput()              — парсинг ответа (JSON/Markdown/plain)
├── runGoalLoop(objective, checks)  — goal-like loop с checkpoints
├── shouldActivatePlanningMode()    — детектор planning mode
└── SessionCompactor                — auto-compaction (80% порог)

ContextBuilder                       — сборка контекста
├── 11 секций (trust boundary)     — TRUSTED vs DATA
├── build() → AgentContext          — полная сборка
├── needsCompaction()               — проверка 80% порога
└── SkillIndex                      — индекс скиллов

AgentSession (actor)                 — состояние сессии
├── events, activePlan, goalState   — durable state
├── todoList, approvalRecords       — задачи и одобрения
├── artifacts, compactionSummaries  — артефакты + compaction
└── providerHealth                  — мониторинг провайдеров
```

### Blueprint coverage — Core Agentic Loop

```
Blueprint §4 (Core loop):
  run_aivibe_agent()           ✅
  context_builder.build()      ✅
  model.generate()             ✅ (Triplex Fallback)
  tool_registry.visibleTools() ✅
  scheduler.order()            ✅
  permissions.evaluate()       ✅
  result_limiter.enforce()     ✅
  max_steps = 8                ✅
  Provider fallback в цикле    ✅

Blueprint §5 (Context):
  11 секций сборки             ✅
  Trust boundary (TRUSTED/DATA) ✅
  Skill index                  ✅

Blueprint §7 (Planning):
  Planning mode triggers       ✅
  Plan artifact                ✅

Blueprint §8 (Goal-like):
  GoalState + checkpoints      ✅
  runGoalLoop()               ✅

Blueprint §9 (Memory):
  Auto-compaction (80%)        ✅
  Compaction summary           ✅
  Durable state                ✅
```

### Итоговая структура Core/AI

```
AIVibe/Core/AI/
├── AIError.swift                    ✅
├── AIProvider.swift                 ✅
├── AIModels.swift                   ✅
├── AIProviderHelpers.swift          ✅
├── AIProviderRouter.swift           ✅ (actor, Triplex fallback)
├── CircuitBreaker.swift             ✅ (actor)
├── CircuitBreakerConfig.swift       ✅
├── Providers/
│   ├── YandexGPTProvider.swift      ✅
│   ├── GigaChatProvider.swift       ✅
│   └── CoreMLProvider.swift         ✅
├── ToolRegistry/                    ← 10 файлов
│   ├── ToolDefinitions.swift        ✅
│   ├── PermissionEngine.swift       ✅
│   ├── ResultLimiter.swift          ✅
│   ├── ToolScheduler.swift          ✅
│   ├── ToolRegistry.swift           ✅
│   └── Tools/ (5 domain tools)      ✅
└── Agent/                           ← NEW (Stage 3)
    ├── AgentSession.swift            ✅ (16.9KB)
    ├── ContextBuilder.swift          ✅ (19.7KB)
    └── AgentLoop.swift               ✅ (24.8KB)
```

---

### Этап 12 — Observability + Evals + Tests (Blueprint §13)

| Дата | Файл | Описание | Статус |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/AI/Agent/AgentObservability.swift` | Observability: TraceEventType (13 типов), TraceRecord (toJSON), ObservabilityCollector actor (record/snapshot/resetMetrics), AgentMetrics (6 метрик), ToolStats (per-tool), EvalProbe (8 probes), EvalProbeRunner actor, EvalProbeResult, EvalSummary. Blueprint §13 | ✅ |
| Июнь 2026 | `AIVibeTests/AI/AgentLoopTests.swift` | Acceptance tests: AgentLoopTests (12), ObservabilityCollectorTests (6), EvalProbeTests (5), EvalProbeRunnerTests (4), TraceRecordTests (2) = 29 тестов. Blueprint §13 | ✅ |

### Сводка Stage 4

```text
2 файла, ~62KB Swift 6.
29 тестов, покрывающих все компоненты агента.
```

**Следующий этап:** Stage 5: Skills and Connectors (Blueprint §10).

---

### Этап 13 — Skills & Connectors (Blueprint §10)

| Дата | Файл | Описание | Статус |
|------|------|----------|--------|
| Июнь 2026 | `AIVibe/Core/AI/Connectors/WildberriesConnector.swift` | Wildberries API v3: searchProducts (GET /content/v3/cards/list), getProductInfo, getCategories, checkStock. Rate limit 100 req/min. WBProduct, WBDimensions, WBCategory, WBStockInfo. ConnectorError, ConnectorID enum | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/Connectors/OzonConnector.swift` | Ozon API v2: searchProducts (POST /v2/product/list), getProductInfo, getCategories, checkStock. Rate limit 100 req/min. OzonProduct, OzonDimensions, OzonCategory, OzonStockInfo | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/Connectors/LockBoxSecretsManager.swift` | Yandex LockBox менеджер секретов: SecretKey (7 ключей), getSecret/getApiKey/getOAuthToken/getClientSecret, кэш в памяти. EnvironmentLoader.loadDotEnv() для локальной разработки. ConnectorHealthMonitor actor: Circuit Breaker для коннекторов (maxFailures=3, cooldown=300s), recordSuccess/recordFailure/isHealthy/status/allStates | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/Skills/SkillIndex.swift` | SkillIndex actor: 3 стандартных скилла (design_advisor, furniture_matcher, budget_optimizer) с полными инструкциями, триггер-фразами, allowed/forbidden tools, валидацией. AgentSkill, SkillState, SkillValidationResult | ✅ |
| Июнь 2026 | `AIVibe/Core/AI/Skills/SkillIntegration.swift` | SkillExecutor actor (load/unload/autoLoad/validate), SkillToolGuard actor (canUseTool/allowedTools/forbiddenTools), SkillActionRequest/SkillActionResult, SkillProvider actor (index + executor + guard). Обработка invoke_skill meta-tool | ✅ |

### Сводка Stage 5

```text
5 файлов, ~60KB Swift 6.

Connectors:
  WildberriesConnector           — WB API v3, search + info + categories + stock
  OzonConnector                  — Ozon API v2, search + info + categories + stock
  LockBoxSecretsManager          — секреты (7 ключей) + EnvironmentLoader
  ConnectorHealthMonitor         — Circuit Breaker для коннекторов

Skills:
  SkillIndex (actor)             — 3 скилла с полными инструкциями
  SkillExecutor (actor)          — загрузка/выгрузка/валидация
  SkillToolGuard (actor)         — проверка доступа к инструментам
  SkillProvider (actor)          — единая точка входа
  SkillActionRequest/Result      — протокол для invoke_skill meta-tool
```

### Blueprint §10 coverage — 100%

```
✅ skill: design_advisor     — analyze_room_scan, recommend_style, read_resource
✅ skill: furniture_matcher  — search_marketplace_furniture, generate_arrangement_plan
✅ skill: budget_optimizer   — search_marketplace_furniture, draft_shopping_list
✅ connector: wildberries_api — read_catalog, read_prices, pinned v3
✅ connector: ozon_api       — read_catalog, read_prices, pinned v2
✅ Yandex LockBox auth       — API keys + OAuth tokens
✅ ConnectorHealthMonitor    — Circuit Breaker для коннекторов
```

### Итоговая структура Core/AI — 20 файлов, ~5200 строк

```
AIVibe/Core/AI/
├── AIError.swift                       ✅
├── AIProvider.swift                    ✅
├── AIModels.swift                      ✅
├── AIProviderHelpers.swift             ✅
├── AIProviderRouter.swift              ✅
├── CircuitBreaker.swift                ✅
├── CircuitBreakerConfig.swift          ✅
├── Providers/ (3 файла)                ✅
├── ToolRegistry/ (10 файлов)           ✅ ← Stages 1-2
│   ├── ToolDefinitions.swift
│   ├── PermissionEngine.swift
│   ├── ResultLimiter.swift
│   ├── ToolScheduler.swift
│   ├── ToolRegistry.swift
│   └── Tools/ (5 domain tools)
├── Agent/ (4 файла)                    ✅ ← Stages 3-4
│   ├── AgentSession.swift
│   ├── ContextBuilder.swift
│   ├── AgentLoop.swift
│   └── AgentObservability.swift
├── Connectors/ (3 файла)               ✅ ← Stage 5 NEW
│   ├── WildberriesConnector.swift
│   ├── OzonConnector.swift
│   └── LockBoxSecretsManager.swift
└── Skills/ (2 файла)                   ✅ ← Stage 5 NEW
    ├── SkillIndex.swift
    └── SkillIntegration.swift
```

### Общий прогресс MVP Agent

```
✅ Stage 1: Tool Registry engine (5 файлов)
✅ Stage 2: Domain tools (5 tools)
✅ Stage 3: Core Agentic Loop (3 файла)
✅ Stage 4: Observability + Tests (2 файла)
✅ Stage 5: Skills & Connectors (5 файлов)
⏳ Stage 6: Integration testing + Launch prep (Blueprint §14)
```

---

*Last updated: June 2026*