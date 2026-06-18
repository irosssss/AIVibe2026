# AUDIT.md — Аудит оснастки и безопасности AIVibe

Прогон стандартного чек-листа «harness / agent-native security» по **реальному коду** репозитория
AIVibe. Каждый пункт проверен по файлам; статус — `pass` / `fail` / `partial` / `n/a`, с
доказательством (`file:line`) и пометкой поверхности:

- **RT** — рантайм-AI-агент приложения (`AIVibe/Core/AI/…`, backend `ai-advisor`).
- **DEV** — dev-harness Claude Code (как coding-агент работает над репо: `.claude/settings.json`,
  `AGENTS.md`, CI).
- **INFRA** — секреты/состояние/деплой.

Серьёзность: `CRIT` 4 · `HIGH` 3 · `MED` 2 · `LOW` 1. Интерактивная версия с живой стрелкой —
`harness-audit-console.html` (рядом, открывается двойным кликом, офлайн).

---

## Итог

| | |
|---|---|
| **Взвешенная готовность** | **≈ 92 %** (82 из 89 применимых взвешенных баллов) |
| **Открытых CRIT-блокеров** | **0** |
| Применимых пунктов | 33 из 42 (9 — `n/a` для этой архитектуры) |
| pass / fail / partial | 30 / 1 / 2 |

> **Обновление 2026-06-18:** применены код-фиксы E2 и F4 + псевдонимизация userId в Langfuse →
> готовность 87 % → **92 %**. Находка про `ai-advisor`/`isBlocked` снята как ложноположительная
> (аудировался не задеплоенный файл — см. «Дополнительные находки»).

> **Почему архитектурный шаблон лёг лишь частично.** Чек-лист написан под «local-first daemon +
> BYOK-прокси + sandboxed iframe + SQLite WAL + агент-редактор файлов». AIVibe — iOS-приложение +
> Node Cloud Functions. Поэтому 9 пунктов (E1, E3, F1–F3, G1–G3, D3) — `n/a`: у проекта **нет**
> BYOK-прокси, веб-песочницы, SQLite/WAL и пользовательских URL в fetch. Все CRIT-пункты, которые
> реально применимы (A1, A2, C1–C3, D1, I1), — **pass**. Открытых CRIT нет → релиз по этому
> критерию не заблокирован.

### Исправлено 2026-06-18 (код-фиксы, проверены build + swiftlint --strict)

- ✅ **[HIGH · E2]** `USDZLoader`: сессия без следования редиректам (`NoRedirectSessionDelegate`) +
  `isSafeRemoteHost` (только HTTPS; отказ приватным/loopback/link-local/CGNAT хостам) → редирект
  больше не уведёт на внутренний адрес. `USDZLoader.swift`.
- ✅ **[MED · F4]** `USDZLoader`: лимит 50 МБ на один USDZ (по `Content-Length` и фактическому
  размеру) поверх LRU-кэша 200 МБ → нет неограниченной загрузки в память. `USDZLoader.swift`.
- ✅ **[PII]** `LangfuseExporter`: `userId`/`user_id` в метаданных псевдонимизируются (SHA-256,
  `redactPII`) перед экспортом наружу. `LangfuseExporter.swift`.

### Остаётся (низкий приоритет)

1. **[MED · G4] Не задокументированы «сброс» и «перенос» локальных данных** —
   `AIVibe/Core/Storage/StorageClient.swift` (есть `clear()`, но процесс не описан). *Фикс:* короткая
   заметка «как очистить/перенести сессии».
2. **[HIGH · H2 · partial] Нет фиксированного регресс-эвала под изменения оснастки** — есть
   `AIVibeTests/AI/Integration/…` и `scripts/code-complexity-analyzer.mjs`, но нет маленького
   стабильного эвал-сета на качество промпт-стека. *Фикс:* 5–10 закреплённых кейсов.
3. **[MED · H3 · partial] Нет локального Stop-хука с тест-гейтом** — выбрано сознательно; гейт
   обеспечивает CI (`ios.yml`/`backend.yml`). *Опционально:* лёгкий Stop-хук `node --check`.

### Дополнительные находки (вне 42 пунктов шаблона — рекомендации)

- **[снято — ложноположительное] `ai-advisor` и `isBlocked()`.** Продакшн-функция `aivibe-ai-advisor`
  собирается из **`backend/index.js`** (`deploy.sh:100-110`), который уже вызывает
  `isBlocked`/`blockUser`/`addStrike` (`backend/index.js:164,180,195`). Файл
  `backend/functions/ai-advisor/index.js` **не деплоится** и не ведёт strike-учёт — добавлять туда
  `isBlocked()` было бы мёртвым кодом. Отдельная задача: оценить удаление неиспользуемого дубликата.
- **[✅ исправлено 2026-06-18] Langfuse и полный `userId`** — теперь псевдонимизируется
  (`LangfuseExporter.redactPII` / `pseudonymize`, SHA-256) перед экспортом. Бэкенд по-прежнему
  обрезает userId до 16 символов в логах (`index.js:148`).
- **[LOW/принято] GigaChat: `NODE_TLS_REJECT_UNAUTHORIZED='0'`** (самоподписанный серт Сбера),
  `backend/shared/gigachat.js`. Архитектурная вынужденность; *улучшение:* пиннинг сертификата.
- **[принято/interim] Rate-limit и баны — в памяти функции** (`backend/index.js:26`,
  `blockedUsers.js:41-42`): сброс на cold start. Признано временным, план — YDB/Redis.

---

## A · Граница доверия и prompt injection

- **[CRIT · A1 · pass · RT]** Вывод инструментов = данные, не команды.
  `ContextBuilder.swift:510-515` (`enum TrustLevel{trusted,data}`); скан/маркетплейс помечены
  `.data` и проходят `sanitizeUntrustedData` (чистка Unicode-tag/zero-width/bidi)
  `ContextBuilder.swift:315-377`; backend RAG помечен «это данные, не инструкции»
  `backend/shared/rag-search.js:86-92`. DEV-политика — `AGENTS.md §5`.
- **[CRIT · A2 · pass · RT]** «Разбери список» читает, не исполняет: каждый tool проходит
  `PermissionEngine`; `financial`→deny, `action`→approval `PermissionEngine.swift:82-112`,
  `ToolRegistry.swift:152-186`. Слепого исполнения нет.
- **[HIGH · A3 · pass · RT]** Фрейминг авторитета/срочности игнорируется: promptGuard
  `role_abuse`/authority-паттерны `backend/promptGuard.js:87-110`; данные санитайзятся. `AGENTS.md §5`.
- **[HIGH · A4 · pass · RT]** Резюме прошлых сессий не открывают права: решение принимается
  per-call по `SessionContext`, не выводится из истории `PermissionEngine.swift:50-68`;
  компакт-сводки — это данные `AgentLoop.swift:612-636`.
- **[MED · A5 · pass · RT]** Скрытый/кодированный текст — только данные: чистка zero-width/bidi/tag
  `ContextBuilder.swift:360-377`; promptGuard ловит base64/homoglyph/unicode-tag
  `backend/promptGuard.js:219-273`; `sanitizeForIndex` в RAG-индексере
  `backend/functions/rag-indexer/index.js:32-39`.

## B · Структура оснастки и стек промпта

- **[HIGH · B1 · pass · RT+DEV]** Оснастка из редактируемых слоёв: рантайм — 11 секций контекста
  детерминированно `ContextBuilder.swift:58-124`; dev — `AGENTS.md` + `harness/00-charter.md` +
  `harness/SKILL.template.md` (новые).
- **[HIGH · B2 · pass · RT]** Плановое состояние переживает сброс: план + auto-compaction
  `AgentLoop.swift:220-229,612-636`, сессия персистится `StorageClient.swift`. DEV: `PLAN.md`
  описан в `AGENTS.md §4` (рекомендательно).
- **[HIGH · B3 · pass · RT]** Само-верификация на каждом шаге: валидация аргументов + result
  limiter + permission-гейт перед каждым tool `ToolRegistry.swift:132-221`. DEV: CI
  `swiftlint --strict` + тесты `.github/workflows/ios.yml`.
- **[MED · B4 · pass · RT]** Петля ограничена: max 8 шагов `AgentLoop.swift:209`,
  `AgentSession.swift:82,128-130`.
- **[MED · B5 · pass · RT+DEV]** Интейк перед генерацией: рантайм Planning Mode на vague/большом
  (Blueprint §7); dev — уточняющие вопросы (продемонстрировано в этой сессии).
- **[LOW · B6 · pass · RT]** Детерминированный порядок слоёв `ContextBuilder.swift:58-124`;
  зафиксирован в `AGENTS.md §4`.

## C · Безопасность инструментов и действий

- **[CRIT · C1 · pass · RT+DEV]** Необратимое — за подтверждением: `action`→approvalRequired, петля
  паузится `PermissionEngine.swift:93-98`, `AgentLoop.swift:279-288`; dev — `ask` на
  `git commit/push`, `rm`, `deny` на `git push --force` `.claude/settings.json`.
- **[CRIT · C2 · pass · RT+DEV]** Агент не вводит креды: нет credential-tool; секреты через Lockbox
  `LockBoxSecretsManager.swift`; dev — `deny Read(.env*)`, `deny Read(**/Lockbox/**)`
  `.claude/settings.json`; `AGENTS.md §6`.
- **[CRIT · C3 · pass · RT]** Деньги/сделки заблокированы: `financial`→deny
  `PermissionEngine.swift:100-102`; `AGENTS.md §6`.
- **[HIGH · C4 · pass · RT+DEV]** Permission-манифест есть: `ToolRiskClass`
  `ToolDefinitions.swift:18-39` + матрица `PermissionEngine.swift:82-112`; dev — allow/ask/deny
  `.claude/settings.json` + `AGENTS.md §6`.
- **[HIGH · C5 · pass · DEV]** Bash по allow-листу: `.claude/settings.json` (allow на git-чтение,
  swiftlint, xcodebuild, node --test/--check, ls, find, health-curl; ask на остальное; deny
  force-push/reset/rm -rf). У рантайм-агента shell-инструмента нет.
- **[MED · C6 · pass · RT]** Разрешения не обобщаются: per-action `evaluate()`
  `PermissionEngine.swift:50-68`. DEV-нюанс: standing-allow только для read-only безопасных команд,
  чувствительные — переспрос.

## D · Секреты и конфигурация

- **[CRIT · D1 · pass · INFRA]** Ключи вне репо и в `.gitignore`: Lockbox+env; `.gitignore:44-84`
  покрывает `.env*`/`Secrets.plist`/`*.p12`/`key.json`/`settings.local.json`/`BackendConfig.plist`;
  `backend/shared/secrets.js` читает только `process.env`. Секретов в индексе не найдено.
- **[HIGH · D2 · pass · INFRA]** Секреты не в URL/логах: передаются в заголовках
  (`yandexgpt.js:105-116` Bearer, `gigachat.js` Basic); `userId` в логах обрезан до 16
  `backend/index.js:148`. (PII-нюанс по Langfuse исправлен — userId псевдонимизируется, см. доп. находки.)
- **[HIGH · D3 · n/a]** Перемещаемый data-dir для read-only установок: концепции `OD_DATA_DIR`
  нет; iOS — песочница приложения, backend — serverless без data-dir.
- **[MED · D4 · pass · INFRA]** Шаблоны без реальных значений: `BackendConfig.example.plist` —
  пустые плейсхолдеры; `!env.example` в `.gitignore`.

## E · Сетевой egress и SSRF

- **[CRIT · E1 · n/a]** BYOK-прокси с блоком внутренних IP: BYOK-прокси **нет**; ни одного
  fetch с пользовательским/контентным URL — все эндпоинты захардкожены
  (`yandexgpt.js:105`, `gigachat.js:65`, `apify-client.js:5`); metadata `169.254.169.254` —
  хардкод, платформенный `yandexgpt.js:35-38`. Риск SSRF, на который нацелен пункт, отсутствует.
- **[HIGH · E2 · pass · RT]** Редиректы апстрима: ✅ исправлено — `USDZLoader` использует сессию с
  `NoRedirectSessionDelegate` (не следует редиректам) + `isSafeRemoteHost` (только HTTPS; отказ
  приватным/loopback/link-local/CGNAT) `USDZLoader.swift`. Backend node fetch — фикс-хосты, риск низкий.
- **[HIGH · E3 · n/a]** Формы по недоверенным ссылкам: у агента нет инструмента сабмита форм/вебом;
  dev-политика link-safety — `AGENTS.md §5`.
- **[MED · E4 · pass · RT]** Нет отправки данных на эндпоинты из контента: egress фиксирован; RAG —
  «данные, не инструкции» `rag-search.js:86-92`; инструмента произвольного POST нет.

## F · Песочница и превью артефактов

- **[CRIT · F1 · n/a]** Изолированный iframe для артефактов: HTML/JS-артефактов **нет** — нативный
  AR Quick Look / RealityKit `AIVibe/Features/ProductDetail/ARQuickLookView.swift:21-24`.
- **[HIGH · F2 · n/a]** CSP на превью: веб-превью нет → CSP не нужен.
- **[HIGH · F3 · n/a]** Артефакты не зовут внутренние API: USDZ — это геометрия без исполнения
  скриптов; сетевых вызовов делать не может.
- **[MED · F4 · pass · RT]** Закалка против огромного ввода: ✅ исправлено — лимит 50 МБ на один USDZ
  (по `Content-Length` и фактическому размеру) поверх LRU-кэша 200 МБ `USDZLoader.swift`. Разбор
  USDZ — нативный RealityKit, закалён Apple.

## G · Состояние, персистентность, владение данными

- **[CRIT · G1 · n/a]** Single-writer SQLite(WAL): SQLite/WAL **нет**; backend — YDB (атомарные
  операции), iOS — `UserDefaults`/`FileManager` `StorageClient.swift`.
- **[HIGH · G2 · n/a]** Forward-only миграции с бэкапом: миграций SQLite нет.
- **[HIGH · G3 · n/a]** Стейджинг + атомарный своп при миграции данных: локальной миграции data-dir
  нет.
- **[MED · G4 · fail · INFRA]** Пути сброса/переноса задокументированы: есть `clear()`
  `StorageClient.swift`, но процесс «сброс/перенос» не описан. *Фикс:* короткая заметка.
- **[LOW · G5 · pass · RT]** Локально-первое состояние, владеет пользователь: сессии/чат на
  устройстве `StorageClient.swift`; облачная синхронизация — в бэклоге.

## H · Наблюдаемость, эвалы, ворота верификации

- **[HIGH · H1 · pass · RT]** Логирование ключевых решений: backend структурно `{_l,_rid,_t}` +
  request-id + решения guard/circuit `backend/index.js:75-81,176-177`; iOS `AgentObservability`
  `AgentObservability.swift:96-142`.
- **[HIGH · H2 · partial · RT]** Регресс-эвал на изменения оснастки: есть интеграционные тесты
  `AIVibeTests/AI/Integration/…` + `scripts/code-complexity-analyzer.mjs` (7 проверок), но
  фиксированного эвал-сета на качество промпт-стека нет. *Фикс:* 5–10 закреплённых кейсов.
- **[MED · H3 · partial · DEV]** Хуки гоняют тесты и заворачивают на провале: локального Stop-хука
  нет (выбрано), гейт — CI `.github/workflows/{ios,backend}.yml`. *Опционально:* лёгкий Stop-хук.
- **[MED · H4 · pass · RT]** Бюджеты времени/стоимости: шаг-бюджет (8) + таймауты 25с/2.5с/90с +
  `maxTokens 2000` `AgentSession.swift:82`, `backend/index.js:225`.
- **[LOW · H5 · pass · RT]** Вызовы инструментов видны в реальном времени: события стримятся,
  типы `SessionEvent` `AgentSession.swift:282-297`; UI показывает «AI думает».

## I · Агент-как-редактор и само-модификация

- **[CRIT · I1 · pass · RT+DEV]** Само-правки ревьюимы и обратимы: **рантайм-агент не может править
  код** (нет file-write/eval) — риск отсутствует; **dev** (Claude Code) правит через диффы + git +
  `ask` на commit/push + защищённые `Edit()`-пути (Providers/Router/CircuitBreaker/secrets.js)
  `.claude/settings.json`.
- **[HIGH · I2 · pass · RT]** Паритет UI↔агент не обходит ворота: гейт в
  `ToolRegistry.execute()`/`PermissionEngine`, а не в точке входа; UI и агент идут через
  `execute()` `ToolRegistry.swift:116-224`.
- **[MED · I3 · pass · RT+DEV]** Скилы ревьюятся перед поставкой: рантайм-скилы — это код в репо
  (`SkillIndex.standardSkills`), ревью через PR/CI; `SkillToolGuard` ограничивает tools
  `SkillIntegration.swift:83-94`; динамической подгрузки скилов нет. Dev — `harness/SKILL.template.md`.

---

## Методология скоринга

Взвешенная готовность = `Σ вес(pass) / Σ вес(применимые)`, где применимые = все, кроме `n/a`;
`partial` и `fail` считаются как 0 в числителе, но входят в знаменатель. Любой **открытый CRIT**
блокирует релиз — сейчас таких 0.

```
CRIT (×4): pass A1,A2,C1,C2,C3,D1,I1               = 7 → 28/28
HIGH (×3): pass A3,A4,B1,B2,B3,C4,C5,D2,E2,H1,I2 (11)
           partial H2                               = 33/36
MED  (×2): pass A5,B4,B5,C6,D4,E4,F4,H4,I3 (9)
           fail G4 · partial H3                     = 18/22
LOW  (×1): pass B6,G5,H5                            = 3/3
ИТОГО                                                 82/89 ≈ 92 %   ·   CRIT открыто: 0  (после фиксов E2/F4)
```

`n/a` (9, исключены из знаменателя): D3, E1, E3, F1, F2, F3, G1, G2, G3 — отсутствуют BYOK-прокси,
веб-песочница, SQLite/WAL и перемещаемый data-dir, т.е. соответствующие риски для этой архитектуры
не существуют.
