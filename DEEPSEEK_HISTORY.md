# DeepSeek History — AIVibe Core Project

> Проект: AIVibe — iOS-приложение для дизайна интерьеров с AR и российским AI  
> Язык: Swift (iOS 17+) + TypeScript (React) + JavaScript (Node.js)  
> DeepSeek V4 Flash — хронология разработки

---

## 📋 Обзор проекта

**AIVibe** — iOS-приложение для дизайна интерьеров. Пользователь фотографирует комнату → AI генерирует дизайн → AR показывает результат.

### Архитектура

```
┌──────────────────────┐     ┌──────────────────┐     ┌─────────────┐
│   AIVibe (iOS App)   │────→│   Backend        │────→│ YandexGPT   │
│   SwiftUI + TCA      │     │   Node.js        │     │ GigaChat    │
│   Swift 5.9          │     │   Cloud Function │     │ CoreML      │
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
| Июнь 2026 | Созданы корневые документы: `DEEPSEEK_PROMPTS.md`, `HOW_TO_USE_v2.md`, `PROJECT_RULES_v2.md`, `SESSION_*` | ✅ |
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
├── Core/
│   ├── AI/          → 7 файлов (protocol, router, circuit breaker, 3 provider, models, errors, helpers) ✅
│   ├── Network/     �� 2 ф��йла (client, errors) ✅
│   ├── Analytics/   → 1 файл (AppMetrica + AnalyticsLogging) ✅
│   └── Storage/     → 1 файл (StorageClient) ✅
├── Features/
│   ├── AIAdvisor/   → ⏳ Ждёт Mac (SwiftUI chat + TCA)
│   └── RoomScan/    → 🟡 Наброски есть, требуется Mac для RealityKit
├── App/DI/          → AppDependencies.swift ✅ (исправлен под реальные типы)
AIVibeTests/
├── AI/             → 2 файла (mock, router tests) ✅
backend/            → 6 файлов (entry, 2 proxies, cache, package, readme) ✅
admin/admin-panel/  → TailAdmin React, готов к доработкам ✅
```

---

## 📎 Полезные ссылки

- [DEEPSEEK_PROMPTS.md](./DEEPSEEK_PROMPTS.md) — все задания DeepSeek по сессиям
- [PROJECT_RULES_v2.md](./PROJECT_RULES_v2.md) — правила проекта
- [HOW_TO_USE_v2.md](./HOW_TO_USE_v2.md) — инструкция по использованию
- [backend/README.md](./backend/README.md) — документация backend
- [admin/admin-panel/DEEPSEEK_HISTORY.md](./admin/admin-panel/DEEPSEEK_HISTORY.md) — история админ-панели

---

*Last updated: June 2026*