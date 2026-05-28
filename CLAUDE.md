# AIVibe — контекст для Claude Code

## Что это за проект

AIVibe — iOS-приложение для AI-ассистента по дизайну интерьеров с поддержкой LiDAR-сканирования
и AR-расстановки мебели. Целевой рынок: Россия. Backend на Yandex Cloud Functions, маркетплейсы
Ozon и Wildberries, AI на YandexGPT 5 + GigaChat-Max + CoreML fallback (Triplex Fallback).

## ⚠️ Терминологическая дисциплина

В этом проекте есть собственные понятия, не путать с Claude Code:

| Термин в проекте | Что это | Где |
|------------------|---------|-----|
| **Agent** | Runtime AI-агент iOS-приложения (для конечных пользователей) | `AIVibe/Core/AI/Agent/` |
| **Skill** | Runtime workflow приложения (`design_advisor`, `furniture_matcher`, `budget_optimizer`) | `AIVibe/Core/AI/Skills/` |
| **Tool** | Domain tool который вызывает runtime Agent | `AIVibe/Core/AI/ToolRegistry/Tools/` |
| **Provider** | AI-провайдер (YandexGPT/GigaChat/CoreML) | `AIVibe/Core/AI/Providers/` |

**Правило:** когда видишь "tool", "skill", "agent", "provider" — это **код приложения**, не dev-tooling Claude Code.

## Технологический стек

- **iOS**: Swift 6.2 (approachable concurrency), iOS 26+, SwiftUI, TCA (Composable Architecture 1.25+)
- **SPM**: swift-composable-architecture, Kingfisher, swift-log, swift-collections
- **Xcode**: 26.2+ (требование App Store с 2026-04-28)
- **Backend**: Node.js 20 (ESM), Yandex Cloud Functions, YDB
- **AI рантайм**: YandexGPT 5 (основной) → GigaChat-Max (fallback) → CoreML (offline)
- **Маркетплейсы**: Ozon API v2, Wildberries API, Apify
- **Аналитика**: AppMetrica
- **CI**: GitHub Actions (macos-26), SwiftLint --strict
- **Деплой**: Fastlane (iOS), `yc serverless function` (backend)

## Структура проекта

```
AIVibe/                          # iOS-приложение
├── App/
│   ├── AppEntry.swift            # @main entry point
│   └── DI/AppDependencies.swift  # Сборка live router
├── Core/
│   ├── AI/                       # AI-подсистема (см. ниже подробно)
│   ├── Network/                  # NetworkClient (URLSession)
│   ├── Storage/                  # StorageClient
│   └── Analytics/                # AppMetricaAnalytics
└── Features/                     # TCA-фичи (AIAdvisor, Marketplace, RoomScan, ARDesigner)

AIVibeTests/                      # XCTest unit + integration
backend/                          # Node 20 ESM (Yandex Cloud Functions)
├── index.js                       # Main entry — ai-advisor proxy с promptGuard, rate limit
├── shared/                        # yandexgpt.js, gigachat.js, triplex-fallback.js, ...
└── functions/                     # ai-advisor, marketplace, image-gen, rag-indexer
```

## Архитектура AI-подсистемы (Blueprint §)

### `AIVibe/Core/AI/` — детально

```
Core/AI/
├── AIProvider.swift              # protocol AIProviderProtocol
├── AIProviderRouter.swift        # actor — Triplex Fallback (§4)
├── AIError.swift                 # enum LocalizedError
├── AIModels.swift                # ChatMessage, AIPrompt, AIResponse
├── AIProviderHelpers.swift
├── CircuitBreaker.swift          # actor (3 fails → 5 min OPEN)
├── CircuitBreakerConfig.swift
│
├── Providers/                    # ⚠️ НЕ ТРОГАТЬ без явного запроса
│   ├── YandexGPTProvider.swift   # Основной для РФ
│   ├── GigaChatProvider.swift    # Резервный для РФ
│   └── CoreMLProvider.swift      # Offline fallback (placeholder с шаблонами)
│
├── Agent/                        # Runtime AI-агент приложения (Blueprint §4-9)
│   ├── AgentLoop.swift           # public actor — главный цикл (max 8 шагов)
│   ├── AgentSession.swift        # public actor — состояние сессии
│   ├── ContextBuilder.swift      # public struct — 11 секций контекста (§5)
│   └── AgentObservability.swift  # Метрики, события
│
├── Skills/                       # Runtime скиллы (Blueprint §10)
│   ├── SkillIndex.swift          # public actor — индекс + 3 стандартных скилла
│   └── SkillIntegration.swift    # SkillExecutor, SkillToolGuard, SkillProvider
│
├── ToolRegistry/                 # Tool Registry (Blueprint §6)
│   ├── ToolRegistry.swift        # public actor — реестр + execute
│   ├── ToolDefinitions.swift     # ToolRiskClass, PermissionDecision, ToolResult
│   ├── PermissionEngine.swift    # Решения allow/deny/approval/sandbox
│   ├── ToolScheduler.swift
│   ├── ResultLimiter.swift
│   └── Tools/                    # 5 domain tools
│       ├── AnalyzeRoomScanTool.swift
│       ├── SearchMarketplaceFurnitureTool.swift
│       ├── RecommendStyleTool.swift
│       ├── GenerateArrangementTool.swift
│       └── DraftShoppingListTool.swift
│
└── Connectors/                   # Внешние системы
    ├── OzonConnector.swift           # actor (rate limit 100/min)
    ├── WildberriesConnector.swift
    └── LockBoxSecretsManager.swift   # actor — Yandex Lockbox обёртка
```

### Ключевые точки (по Blueprint)

- **§4 Core Agentic Loop** — `AgentLoop.run(request:session:)`, max 8 шагов, Triplex Fallback внутри
- **§5 Context Architecture** — `ContextBuilder.build(session:...)`, 11 секций, trust boundary (trusted/data)
- **§6 Tool Registry** — `ToolRegistry.execute(call:)`, permission check, result limiter
- **§7 Planning Mode** — активируется на больших комнатах, бюджете > 500K ₽, vague phrases
- **§8 Goal-like Loop** — `AgentLoop.runGoalLoop()` для long-running задач, checkpoints, stop rules
- **§9 Auto-compaction** — `SessionCompactor.compactAndRehydrate()`, при > 80% контекста (16K символов)
- **§10 Skills & Connectors** — `SkillIndex.standardSkills` (design_advisor, furniture_matcher, budget_optimizer), `OzonConnector`, `WildberriesConnector`
- **§12 Audit** — `ApprovalRecord`, риск-классы (`readPublic` → `financial`)
- **§13 Observability** — `AgentObservability`, AppMetrica события, Circuit Breaker метрики
- **§14 Launch prep** — `AIVibeTests/AI/Integration/AgentIntegrationTests.swift`

## Конвенции кода

### Swift
- Комментарии и логи **на русском** (документация — тоже)
- Все типы `public` для внешнего API модуля
- Errors как `enum: LocalizedError, Sendable, Equatable`
- Изменяемое состояние — через `actor`, не `class`
- Все DTO — `Sendable + Codable + Equatable`
- Логирование — `swift-log` (`Logger(label: "ai.module")`)
- TCA: `@Reducer struct Feature`, `@ObservableState`, `enum Action`
- Никакого `Alamofire` — только `URLSession async/await` (см. `NetworkClient.swift`)

### Backend (Node)
- ESM only (`"type": "module"`)
- **Никаких внешних npm-зависимостей** (минимальный бандл Yandex Cloud Function)
- Все HTTP-вызовы через `fetch`, не `axios`
- Логи структурированные: `{ _l, _rid, _t, ... }`
- Rate limit и Circuit Breaker — обязательно для AI endpoints

### Безопасность
- **Никогда** не коммитить секреты, IAM-токены, client_secret
- API-ключи только через `process.env` / Yandex Lockbox / `LockBoxSecretsManager`
- В iOS-бандле **нет** ключей AI-провайдеров
- `promptGuard.js` и `blockedUsers.js` — обязательно перед AI-вызовом в backend

## Что НЕ менять без явного запроса

### Runtime AI (требование рынка РФ)
- `AIVibe/Core/AI/Providers/YandexGPTProvider.swift`
- `AIVibe/Core/AI/Providers/GigaChatProvider.swift`
- `AIVibe/Core/AI/AIProviderRouter.swift` (Triplex Fallback)
- `backend/shared/yandexgpt.js`
- `backend/shared/gigachat.js`
- `backend/shared/triplex-fallback.js`

### Архитектурное ядро
- `AIVibe/Core/AI/Agent/AgentLoop.swift` (только bugfix, не редизайн)
- `AIVibe/Core/AI/Skills/SkillIndex.swift` (только добавление новых, не правки существующих)
- `AIVibe/Core/AI/ToolRegistry/ToolRegistry.swift` (только регистрация новых tools)
- `AIVibe/Core/AI/CircuitBreaker.swift` и `CircuitBreakerConfig.swift` (синхронизированы с backend)

### Инфраструктура
- `Package.swift` и `Package.resolved` (стабильность зависимостей)
- `.swiftlint.yml` (CI падает на изменениях)
- `.github/workflows/ios.yml`
- `Fastlane/` (деплойные секреты)

### Документация
- `SESSION_*.md` (история разработки, append-only)
- `PROJECT_RULES_v2.md` (источник правил)
- `DEEPSEEK_*.md` (промпт-история)

**При сомнениях — спросить пользователя ДО правки.**

## Команды для типовых задач

Эти команды находятся в `permissions.allow` (см. `.claude/settings.json`) — выполняются без подтверждения.

```bash
# iOS тесты (полный suite)
xcodebuild test -scheme AIVibe -destination "platform=iOS Simulator,name=iPhone 17,OS=26.3.1" -quiet

# iOS lint (строгий, как в CI)
swiftlint --strict

# iOS build (Debug)
xcodebuild build -scheme AIVibe -destination "platform=iOS Simulator,name=iPhone 17,OS=26.3.1" -configuration Debug -quiet

# Backend тесты
cd backend && node --test

# Backend проверка синтаксиса
node --check backend/index.js
node --check backend/functions/ai-advisor/index.js

# Анализ сложности кода (7 архитектурных проверок: рассинхрон CB, N+1, full scan, event loss и т.д.)
# Exit code 1 при наличии WARN — подходит для CI gate
node scripts/code-complexity-analyzer.mjs

# Health check production backend (через AIVIBE_BACKEND_HEALTH_URL из settings.local.json)
curl -s "$AIVIBE_BACKEND_HEALTH_URL"

# SPM
swift package show-dependencies
swift package resolve
```

Эти команды требуют подтверждения (`permissions.ask`):

```bash
git commit ...                 # коммит руками или через подтверждение
git push ...                   # пуш руками или через подтверждение
yc serverless function ...     # деплой в Yandex Cloud
fastlane ...                   # деплой iOS
npm install ...                # риск добавления нежелательных зависимостей
rm ...                         # удаление файлов
```

## Стиль ответа Claude

- Отвечать **на русском** (если в чате на русском)
- Перед правкой кода — обязательно прочитать соответствующий файл
- Перед запуском destructive команды (rm, git push --force, deploy) — спросить
- При изменении AI-логики — упомянуть Blueprint § для контекста
- При работе с runtime Agent loop — учитывать ограничения: max 8 шагов, auto-compaction на 80%, Triplex Fallback
- Не создавать новые `SESSION_*.md` без явного запроса
- Не создавать markdown-файлы документации спонтанно (`README.md` и т.п.) — только по запросу

## Где искать дополнительный контекст

| Вопрос | Файл |
|--------|------|
| История разработки | `SESSION_01_init.md` ... `SESSION_07_marketplace_apify.md` |
| Бизнес-правила, ограничения | `PROJECT_RULES_v2.md` |
| Архитектурные решения | `complexity-report.md` |
| Промпт-инструкции | `DEEPSEEK_PROMPTS.md`, `DEEPSEEK_HISTORY.md` |
| Архив устаревших планов | `docs/archive/` |
