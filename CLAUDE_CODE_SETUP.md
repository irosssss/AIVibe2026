# AIVibe — Настройка Claude Code как dev environment

> Дата: 2026-05-26 (v2 — упрощённая после анализа проекта)
> Цель: настроить Claude Code (Opus 4.7) как **инструмент разработки** для AIVibe.
> Runtime AI-провайдеры (YandexGPT 5, GigaChat-Max, CoreML fallback) **остаются как есть** — это требование рынка РФ.
> Конфиги в этом плане живут только в репозитории. Они **не попадают** в App Store-бандл и не деплоятся в Yandex Cloud.

---

## ⚠️ Что важно понять про этот проект

В AIVibe слова **«Agent»** и **«Skill»** УЖЕ ЗАНЯТЫ runtime-кодом приложения:

| Термин | Где живёт | Назначение |
|--------|-----------|-----------|
| **Agent** | `AIVibe/Core/AI/Agent/` (`AgentLoop`, `AgentSession`, `ContextBuilder`, `AgentObservability`) | Главный цикл AI-агента ВНУТРИ iOS-приложения. Помогает пользователю в дизайне интерьеров. Работает с YandexGPT/GigaChat через Triplex Fallback |
| **Skill** | `AIVibe/Core/AI/Skills/` (`SkillIndex`, `SkillIntegration`, `AgentSkill`) | Reusable workflows ВНУТРИ приложения: `design_advisor`, `furniture_matcher`, `budget_optimizer`. Активируются триггер-фразами пользователя |
| **Tool** | `AIVibe/Core/AI/ToolRegistry/Tools/` | 5 tools которые runtime Agent вызывает (`analyze_room_scan`, `search_marketplace_furniture` и т.д.) |

**Следствие:** в `.claude/` папке мы **СОЗНАТЕЛЬНО НЕ создаём** ни `skills/`, ни `commands/`, ни `agents/`. Иначе будет терминологический хаос — две разные сущности с одинаковыми именами в одном репозитории.

Claude Code прекрасно работает без кастомных slash-команд и skills. Достаточно `CLAUDE.md` + правильно настроенных `permissions`.

---

## Что мы делаем (минимальный набор)

| ✅ Делаем | ❌ НЕ делаем |
|----------|-------------|
| `CLAUDE.md` — главный файл контекста | Не создаём `.claude/skills/` (конфликт с runtime) |
| `.claude/settings.json` — permissions, env | Не создаём `.claude/commands/` (избыточно для этого проекта) |
| `.claude/settings.local.json` — локальные секреты | Не подключаем MCP-серверы (минимизируем attack surface) |
| Обновление `.gitignore` | Не правим рантайм Swift / Node код |
| Удаление мусора (`agents-best-practices/`, `.polza/`) ✅ **уже сделано** | Не меняем CI / Fastlane / Lockbox |

---

## Структура того, что появится в репозитории

```
AIVibe2026/
├── CLAUDE.md                    ← НОВЫЙ. Главный файл контекста для Claude
├── .claude/                     ← НОВАЯ ПАПКА (только 2 файла, ничего больше)
│   ├── settings.json             ← Project-level (в git)
│   └── settings.local.json       ← Локальные (в .gitignore)
├── .gitignore                   ← ОБНОВИТЬ (3 строки)
└── docs/
    └── archive/
        └── MIGRATION_TO_CLAUDE_obsolete.md  ← УЖЕ ПЕРЕМЕЩЁН
```

Итого: **2 новых файла, 1 правка `.gitignore`**. Больше ничего.

---

## Шаг 1 — `CLAUDE.md` (в корне репозитория)

Этот файл Claude Code читает **в начале каждой сессии**. Здесь — всё что мне нужно знать про проект, чтобы не ломать существующее.

### Создать `/Users/dmitrijzdanov/Documents/AIVibe2026/CLAUDE.md`:

```markdown
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
- **Backend**: Node.js 20 (ESM), Yandex Cloud Functions, YDB
- **AI рантайм**: YandexGPT 5 (основной) → GigaChat-Max (fallback) → CoreML (offline)
- **Маркетплейсы**: Ozon API v2, Wildberries API, Apify
- **Аналитика**: AppMetrica
- **CI**: GitHub Actions (macos-14), SwiftLint --strict
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
- `docs/archive/PROJECT_RULES_v2.md` (легаси-правила DeepSeek/Windows-эры — архив; актуальный источник = `CLAUDE.md`)
- `docs/archive/DEEPSEEK_*.md` (промпт-история, легаси — архив)

**При сомнениях — спросить пользователя ДО правки.**

## Команды для типовых задач

Эти команды находятся в `permissions.allow` (см. `.claude/settings.json`) — выполняются без подтверждения.

```bash
# iOS тесты (полный suite)
xcodebuild test -scheme AIVibe -destination "platform=iOS Simulator,name=iPhone 15,OS=18.0" -quiet

# iOS lint (строгий, как в CI)
swiftlint --strict

# iOS build (Debug)
xcodebuild build -scheme AIVibe -destination "platform=iOS Simulator,name=iPhone 15,OS=18.0" -configuration Debug -quiet

# Backend тесты
cd backend && node --test

# Backend проверка синтаксиса
node --check backend/index.js
node --check backend/functions/ai-advisor/index.js

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
| Бизнес-правила, ограничения | `STRATEGY.md`, `CLAUDE.md` (легаси: `docs/archive/PROJECT_RULES_v2.md`) |
| Архитектурные решения | `complexity-report.md` |
| Промпт-инструкции (архив) | `docs/archive/DEEPSEEK_PROMPTS.md`, `docs/archive/DEEPSEEK_HISTORY.md` |
| Архив устаревших планов | `docs/archive/` |
```

---

## Шаг 2 — `.claude/settings.json` (project-level, в git)

Этот файл коммитится. Содержит permissions, env-переменные. **Hooks НЕ добавляем** — они могут навязчиво вмешиваться в код. Lint запускается явно по запросу.

### Создать `.claude/settings.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Read(**)",
      "Glob(**)",
      "Grep(**)",
      "Bash(git status:*)",
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "Bash(git branch:*)",
      "Bash(git show:*)",
      "Bash(git add:*)",
      "Bash(swiftlint:*)",
      "Bash(swift package show-dependencies:*)",
      "Bash(swift package resolve:*)",
      "Bash(xcodebuild build:*)",
      "Bash(xcodebuild test:*)",
      "Bash(xcodebuild -showBuildSettings:*)",
      "Bash(node --test:*)",
      "Bash(node --check:*)",
      "Bash(ls:*)",
      "Bash(find . -type f -name:*)",
      "Bash(curl -s https://functions.yandexcloud.net/*/health:*)"
    ],
    "ask": [
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(yc serverless:*)",
      "Bash(yc lockbox:*)",
      "Bash(fastlane:*)",
      "Bash(npm:*)",
      "Bash(rm:*)",
      "Bash(mv:*)",
      "Edit(Package.swift)",
      "Edit(Package.resolved)",
      "Edit(.github/**)",
      "Edit(Fastlane/**)",
      "Edit(SESSION_*.md)",
      "Edit(docs/archive/**)",
      "Edit(.swiftlint.yml)",
      "Edit(AIVibe/Core/AI/Providers/**)",
      "Edit(AIVibe/Core/AI/AIProviderRouter.swift)",
      "Edit(AIVibe/Core/AI/CircuitBreaker*.swift)",
      "Edit(backend/shared/yandexgpt.js)",
      "Edit(backend/shared/gigachat.js)",
      "Edit(backend/shared/triplex-fallback.js)",
      "Edit(backend/shared/secrets.js)",
      "WebFetch(domain:*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(git push -f*)",
      "Bash(git reset --hard*)",
      "Bash(rm -rf /:*)",
      "Bash(rm -rf ~:*)",
      "Read(.env)",
      "Read(.env.*)",
      "Read(**/secrets/**)",
      "Read(**/.ssh/**)",
      "Read(**/Lockbox/**)"
    ]
  }
}
```

> **Что важно в этом конфиге:**
> - `Read(**)` — Claude может читать любые файлы проекта (кроме явных `deny`)
> - Тесты/lint/build — без подтверждения (быстрая итерация)
> - Все правки runtime AI-файлов (Providers, Router, CircuitBreaker) — **только через `ask`**
> - Деплой и git push — **только через `ask`**
> - Никаких hooks: lint вызывается явно «прогони swiftlint» или вы заходите и проверяете руками

---

## Шаг 3 — `.claude/settings.local.json` (личное, в .gitignore)

Этот файл **НЕ коммитим**. Здесь — личные URL функций, токены, переопределения permissions для конкретного разработчика.

### Создать `.claude/settings.local.json`:

```json
{
  "env": {
    "AIVIBE_BACKEND_HEALTH_URL": "https://functions.yandexcloud.net/REPLACE_WITH_FUNCTION_ID/health"
  }
}
```

> Перед использованием — заменить `REPLACE_WITH_FUNCTION_ID` на реальный ID Cloud Function.

---

## Шаг 4 — Обновить `.gitignore`

### Добавить в `/Users/dmitrijzdanov/Documents/AIVibe2026/.gitignore`:

```gitignore
# Claude Code
.claude/settings.local.json
.claude/cache/
.claude/logs/
```

---

## Шаг 5 — Применить и проверить

```bash
# 1. Создать файлы (руками, по шаблонам выше)
# 2. Перезапустить Claude Code сессию
# 3. В новой сессии проверить:
#    - Claude видит CLAUDE.md (упоминает архитектуру AIVibe в ответах)
#    - /test или прямой запрос "запусти тесты" — выполняется без подтверждения
#    - "удали файл X" — запрашивает подтверждение
#    - "поправь YandexGPTProvider" — запрашивает подтверждение
```

---

## Почему НЕ делаем кастомные slash-команды

В первой версии этого плана я предлагал 11 slash-команд (`/test`, `/lint`, `/add-tool`, ...) и 3 кастомных Skill. После анализа проекта решил это **убрать**. Причины:

1. **Терминологический конфликт** — у вас уже есть runtime Skills и Agent. Добавление `.claude/skills/` создаёт два разных понятия с одним именем.
2. **Permissions достаточно** — если `Bash(xcodebuild test:*)` в `allow`, я выполню тесты по запросу «запусти тесты» без обёртки `/test`.
3. **Меньше файлов — меньше поддержки** — каждая slash-команда это `.md` файл, который надо обновлять при изменении проекта.
4. **Гибкость > шаблоны** — slash-команды жёстко зашиты. Прямой запрос на естественном языке позволяет адаптировать действие под контекст.
5. **Skills для dev-задач избыточны для домена** — формат Anthropic Skills (как в `ericosiu/ai-marketing-skills`) рассчитан на сложные multi-step workflows с reference-файлами. Для AIVibe этого пока не требуется.

**Если позже захочется** — добавите по одной команде когда станет ясно, что без неё неудобно. Принцип YAGNI.

---

## Почему НЕ подключаем MCP-серверы

MCP (Model Context Protocol) серверы — внешние подключения для Claude. Для AIVibe не подключаем:

1. **Минимизация attack surface** — у проекта код, идущий в App Store и Yandex Cloud. Внешние MCP-источники могут содержать инъекции.
2. **Локальной файловой системы достаточно** — Claude Code уже имеет встроенный Read/Edit/Bash для работы с проектом.
3. **GitHub MCP не нужен** — `gh` CLI и `git` через Bash покрывают все задачи.
4. **Yandex Cloud MCP** не существует официально, а сторонним доверять для прод-секретов — риск.

Если в будущем понадобится — добавится отдельной задачей с обсуждением.

---

## Сводка изменений в репозитории

| Что | Действие |
|-----|----------|
| `docs/archive/MIGRATION_TO_CLAUDE_obsolete.md` | ✅ Уже перемещён (старый ошибочный план) |
| `agents-best-practices/` | ✅ Удалена (была пустая) |
| `.polza/` | ✅ Удалена (артефакт Polza IDE) |
| `CLAUDE.md` | ⏳ Создать в корне (Шаг 1) |
| `.claude/settings.json` | ⏳ Создать (Шаг 2) |
| `.claude/settings.local.json` | ⏳ Создать локально (Шаг 3) |
| `.gitignore` | ⏳ Добавить 3 строки (Шаг 4) |
| Runtime код (Swift / Node) | ❌ Не трогаем |
| CI / Lockbox / Fastlane | ❌ Не трогаем |

**Итого:** 2 новых файла + 1 правка `.gitignore`. Ноль изменений в коде приложения.

---

## Принципы безопасности (коротко)

1. **`.claude/settings.local.json` НИКОГДА не коммитим**
2. **Permissions в `deny` нельзя смягчать без обсуждения** — даже временно
3. **Claude НЕ деплоит автоматически** — `yc serverless` и `fastlane` всегда через `ask`
4. **WebFetch — только через `ask`** — Claude не должен случайно скачивать произвольные URL
5. **Runtime AI-файлы — только через `ask`** — случайная правка `YandexGPTProvider.swift` ломает прод в РФ
6. **Никаких hooks** — автоматическое выполнение `swiftlint --fix` или подобного может незаметно менять код

---

## Что дальше (без спешки)

После применения плана работаете как обычно: пишете в чат «добавь сюда обработку ошибки», «прогони тесты», «покажи health backend» — я делаю по `permissions`.

Если через 1-2 недели окажется, что какая-то команда повторяется десятки раз — тогда добавим её как `.claude/commands/<name>.md` точечно. Но **не превентивно**.

Если появится повторяющийся сложный workflow (например, миграция БД, генерация бойлерплейта на несколько файлов) — можно создать один Skill в `.claude/skills/<name>/SKILL.md`. Но опять же — **только когда станет ясно, что без него неудобно**.

Принцип: **start minimal, grow on demand**.
