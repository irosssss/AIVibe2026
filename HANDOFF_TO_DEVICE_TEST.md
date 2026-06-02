# AIVibe — что сделано и что осталось до теста на iPhone

> Этот файл — «передача дел». Слева то, что **Claude уже сделал в коде**,
> справа — **шаги, которые можешь сделать только ты** (нужны твои аккаунты,
> деньги, телефон и Mac). Язык — простой, по принципу «что и зачем».
>
> Дата: 2026-06-03. Ветка: `claude/bold-jackson-e41a73`.

---

## 1. Что уже сделано (бэкенд готов к деплою)

Весь серверный код приведён в рабочее состояние для **Yandex Cloud Functions**
(никаких виртуалок и Kubernetes — только serverless + Apify, как ты и хотел).

| Файл | Что было не так | Что стало |
|------|-----------------|-----------|
| `backend/blockedUsers.js` | хранил баны в файле — в облаке файл исчезает при перезапуске | хранение в памяти (Map), логика блокировок не тронута |
| `backend/shared/yandexgpt.js` | токен брался из переменной, протухал через 12 ч | новая функция `getIamToken()` берёт свежий токен из metadata-сервиса облака |
| `backend/shared/ydb-client.js` | заглушка на 16 строк | настоящий клиент базы YDB (Document API), 195 строк, с «мягкой деградацией» без базы |
| `backend/shared/secrets.js` | не знал про переменные базы | добавлены `YDB_DOCUMENT_API_ENDPOINT`, `YDB_DATABASE` |
| `backend/functions/marketplace/index.js` | вызывал несуществующий Apify-актор | параллельный поиск Wildberries + Ozon, нормализация, фильтр по бюджету |
| `backend/deploy.sh` | **не существовал** | скрипт деплоя всех 4 функций одной командой |
| `backend/api-gateway.yaml` | **не существовал** | конфиг единого входа (URL → нужная функция) |
| `.github/workflows/backend.yml` | **не существовал** | автодеплой в облако после тестов (по желанию) |

**Проверено:** все файлы проходят `node --check`, модули реально импортируются и
работают (блокировки, сериализация базы, мягкая деградация без облака — всё ✅).

> ⚠️ Одно «но» по маркетплейсу: ID Apify-акторов (`epctex/wildberries-scraper`,
> `epctex/ozon-scraper`) и **названия полей в их выдаче** нужно сверить на
> apify.com/store во время smoke-теста (Фаза 3, тест 3). Если поля называются
> иначе — normalize-функции в `marketplace/index.js` подправим за минуту.

---

## 2. Карта оставшихся шагов

```
ТЫ: Фаза 0  Завести 4 аккаунта (Apify, GigaChat, AppMetrica, Apple)
ТЫ: Фаза 1  Yandex Cloud: SA, Lockbox, YDB, Storage, регистрация функций
ТЫ: Фаза 3  Запустить deploy.sh, создать API Gateway, smoke-тесты
МЫ ВМЕСТЕ:  Фаза 4  iOS на твоём Mac (см. раздел 5 — план изменился!)
ТЫ: Фаза 5  Тест на iPhone: скан → AI → AR → маркетплейс
```

Подробные команды Фаз 0/1/3/5 — в большом плане `PLAN_TO_DEVICE_TEST.md`
(он остаётся верным для этих фаз). Ниже — выжимка самого нужного.

---

## 3. Фаза 0 — какие аккаунты завести и что оттуда скопировать

| Сервис | Зачем | Что скопировать |
|--------|-------|-----------------|
| **Apify** (apify.com) | поиск товаров на WB/Ozon | Settings → Integrations → **Personal API token** |
| **GigaChat** (developers.sber.ru/gigachat) | запасной AI, если YandexGPT недоступен | **Client ID** и **Client Secret** (раздел API → OAuth) |
| **AppMetrica** (appmetrica.yandex.com) | аналитика событий | Добавить приложение → iOS → **API key** |
| **Apple Developer** | подпись приложения для iPhone | для разработки хватит **бесплатного** Apple ID; платный ($99) — для TestFlight позже |

Сложи всё в заметку — эти значения пойдут в Lockbox (Фаза 1) и в iOS (Фаза 4).

---

## 4. Фазы 1 и 3 — Yandex Cloud и деплой (выжимка команд)

> Предусловие: установлен `yc` CLI и сделан `yc init`. Полные пояснения — в
> `PLAN_TO_DEVICE_TEST.md`, разделы 5 и 7.

### 4.1 Инфраструктура (Фаза 1)

```bash
export YC_FOLDER_ID=$(yc config get folder-id)

# Сервисный аккаунт + 5 ролей (в т.ч. ai.languageModels.user — без неё YandexGPT даст 401)
yc iam service-account create --name aivibe-sa
export SA_ID=$(yc iam service-account get aivibe-sa --format json | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
for role in ydb.editor lockbox.payloadViewer storage.editor serverless.functions.invoker ai.languageModels.user; do
  yc resource-manager folder add-access-binding --id $YC_FOLDER_ID --role $role --subject serviceAccount:$SA_ID
done
yc iam key create --service-account-id $SA_ID --output key.json   # key.json уже в .gitignore — не коммить!

# Lockbox с секретами (подставь свои значения)
yc lockbox secret create --name aivibe-secrets
export LOCKBOX_ID=$(yc lockbox secret get aivibe-secrets --format json | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
APP_TOKEN=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")   # СОХРАНИ — нужен в iOS!
# дальше: yc lockbox secret add-version с 8 ключами (см. план §5.3 и §5.4)

# YDB (база) + Object Storage + регистрация 4 функций — команды в плане §5.4–5.5
```

8 ключей в Lockbox: `YANDEXGPT_FOLDER_ID`, `GIGACHAT_CLIENT_ID`,
`GIGACHAT_CLIENT_SECRET`, `APP_TOKEN`, `APIFY_API_TOKEN`,
`YDB_DOCUMENT_API_ENDPOINT`, `YDB_DATABASE`, `NODE_TLS_REJECT_UNAUTHORIZED=0`.

### 4.2 Деплой (Фаза 3)

```bash
# Переменные окружения для скрипта
export YC_FOLDER_ID=$(yc config get folder-id)
export SA_ID=$(yc iam service-account get aivibe-sa --format json | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
export LOCKBOX_ID=$(yc lockbox secret get aivibe-secrets --format json | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")

# Деплой всех 4 функций
bash backend/deploy.sh

# Подставить реальные ID функций и SA в api-gateway.yaml (инструкция-команды — в шапке самого файла)
# Создать шлюз и получить URL:
yc serverless api-gateway create --name aivibe-gateway --spec backend/api-gateway.yaml
export GATEWAY_URL="https://$(yc serverless api-gateway get aivibe-gateway --format json | python3 -c "import sys,json;print(json.load(sys.stdin)['domain'])")"
echo "API Gateway URL: $GATEWAY_URL   # ← сохрани, понадобится в iOS"
```

Затем 4 smoke-теста (`/health`, `/analyze`, `/marketplace/search`, rate-limit) —
команды в плане §7.4. **Не переходи к iOS, пока `/analyze` не вернёт ответ.**

---

## 5. Фаза 4 — iOS (план ИЗМЕНИЛСЯ — важно прочитать)

### Почему план был неверным

В `PLAN_TO_DEVICE_TEST.md` Фаза 4 написана под проект Xcode (`AIVibeApp.xcodeproj`)
с файлами `.xcconfig`. **На самом деле проект — это Swift Package** (`Package.swift`),
там нет Xcode-проекта и `.xcconfig` так не работают.

И главное: **сейчас приложение НЕ ходит на твой бэкенд.** Оно:
- зовёт YandexGPT/GigaChat **напрямую с телефона** (секреты из переменных окружения);
- маркетплейс показывает **выдуманные (mock) товары**, а не реальные.

То есть «подключить iOS к бэкенду» — это **полноценная доработка**, а не вставка
одного URL. Поэтому ты выбрал «сделать iOS в следующий заход на Mac» — правильно.

### Что именно нужно сделать (я сделаю это с тобой на Mac)

1. **`AIVibe/Core/AppConfig.swift`** (новый) — единое место для настроек:
   `apiBaseURL` (URL шлюза), `appToken` (тот самый APP_TOKEN), `appMetricaKey`,
   и стабильный `userId` (генерируем один раз, храним в UserDefaults).

2. **`BackendProvider`** (новый, рядом с `YandexGPTProvider`) — провайдер, который
   шлёт `POST {apiBaseURL}/analyze` с телом `{prompt, userId}` и заголовком
   `x-app-token`, и разбирает ответ `{text, provider, latencyMs}`.
   Триплекс-фолбэк (YandexGPT→GigaChat→кэш) уже происходит **на сервере**, поэтому
   на телефоне остаётся только этот один провайдер + `CoreMLProvider` для офлайна.

3. **`AIVibe/App/DI/AppDependencies.swift`** — заменить прямые
   `YandexGPTProvider`/`GigaChatProvider` на `[BackendProvider(), CoreMLProvider()]`.
   Так секреты (IAM, GigaChat) **уходят с телефона на сервер** — это безопасно и
   правильно (152-ФЗ, лимиты, защита от инъекций — всё на бэкенде).

4. **`SearchMarketplaceFurnitureTool.swift`** — заменить mock на реальный
   `POST {apiBaseURL}/marketplace/search` и убрать обёртку `#if canImport(FoundationNetworking)`
   (из-за неё на устройстве всегда срабатывал mock).

5. **AppMetrica через SPM** (ты выбрал этот вариант). В `Package.swift`:

   ```swift
   // в dependencies:
   .package(url: "https://github.com/appmetrica/appmetrica-sdk-ios", from: "6.0.0"),
   // в target "AIVibe" → dependencies:
   .product(name: "AppMetricaCore", package: "appmetrica-sdk-ios"),
   ```

   > Версия **6.0.0+** (в плане был устаревший `4.0.0`; актуальный релиз — 6.3.0).
   > Затем в `AppEntry.swift` — активация в `init()`, а в
   > `AppMetricaAnalytics.swift` заменить заглушку-лог на `AppMetrica.reportEvent(...)`.
   > Тест-мок `MockAnalytics` трогать не нужно — он продолжит работать.

6. **Подпись и запуск** в Xcode: Team = твой Apple ID, уникальный Bundle ID,
   на iPhone включить «Режим разработчика» и доверить сертификат. Запуск — Cmd+R.

> Когда вернёшься на Mac с готовым `GATEWAY_URL` и `APP_TOKEN` — скажи мне
> «делаем iOS», и я выполню пункты 1–5 кодом и соберу проект в симуляторе для
> проверки компиляции. Тест на самом iPhone (камера/LiDAR/AR) — за тобой.

---

## 6. Короткий чеклист

```
БЭКЕНД (готово)
  ✅ blockedUsers in-memory, getIamToken, ydb-client, secrets, marketplace
  ✅ deploy.sh, api-gateway.yaml, backend.yml
  ✅ node --check + рантайм-проверка пройдены

ТВОИ ШАГИ
  ☐ Фаза 0: аккаунты Apify / GigaChat / AppMetrica / Apple
  ☐ Фаза 1: SA+роли, Lockbox(8 ключей), YDB(3 таблицы), Storage, 4 функции
  ☐ Фаза 3: bash backend/deploy.sh → заполнить api-gateway.yaml → создать шлюз
  ☐ Фаза 3: smoke-тесты /health и /analyze зелёные
  ☐ сверить Apify-акторы и поля выдачи (тест маркетплейса)

iOS (СЛЕДУЮЩИЙ ЗАХОД, ВМЕСТЕ НА MAC)
  ☐ AppConfig + BackendProvider + правка AppDependencies
  ☐ реальный маркетплейс вместо mock
  ☐ AppMetrica через SPM (6.0.0+)
  ☐ подпись, запуск на iPhone, E2E (Фаза 5)
```

---

*Файлы бэкенда изменены, но НЕ закоммичены — скажи, когда коммитить.*
