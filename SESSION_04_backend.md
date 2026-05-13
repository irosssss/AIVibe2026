# СЕССИЯ 4 — Backend: Yandex Cloud Function

> Режим: обычный чат (не нужен Xcode контекст)
> Добавь: @PROJECT_RULES.md

---

Реализуй серверную функцию-прокси для AI на Yandex Cloud.

## Задача
Создай Yandex Cloud Function `aiAdvisor` на Node.js 20, которая:
1. Принимает запрос от iOS-клиента
2. Пробует YandexGPT → GigaChat → возвращает cached ответ
3. Скрывает все API-ключи от клиента
4. Имеет rate limiting (20 req/min per user)

## Файлы для создания

### index.js — основная функция
```javascript
// Точка входа Yandex Cloud Function
// Triplex fallback: YandexGPT → GigaChat → Cache
module.exports.handler = async (event, context) => { ... }
```

Логика:
- Parse request body (prompt, userId, imageBase64?)
- Validate App Check token (header: X-Firebase-AppCheck)
- Check rate limit (Yandex Lockbox → Redis / in-memory)
- Try YandexGPT (timeout 25s)
- On fail → Try GigaChat (timeout 25s)
- On fail → Return cached similar response
- Log to Yandex Cloud Logging
- Return response с полем `provider: "yandexgpt"|"gigachat"|"cache"`

### secrets.js — получение секретов из Yandex Lockbox
```javascript
// Никогда не хардкодить ключи
// Использовать Yandex Lockbox API
async function getSecrets() {
  // GET https://payload.lockbox.api.cloud.yandex.net/lockbox/v1/secrets/{id}/payload
}
```

### yandexgpt.js — клиент YandexGPT
Endpoint: `https://llm.api.cloud.yandex.net/foundationModels/v1/completion`
Auth: IAM-токен (обновлять каждые 12 часов)
Модель: `gpt://folder-id/yandexgpt-5/latest`

### gigachat.js — клиент GigaChat
Auth: OAuth 2.0
Endpoint: `https://gigachat.devices.sberbank.ru/api/v1/chat/completions`
Важно: отключить проверку SSL (self-signed cert) — добавить комментарий о риске

### package.json
Зависимости только нативные или минимальные (node-fetch или встроенный fetch)

## Deployment
Напиши команды для деплоя через Yandex CLI:
```bash
yc serverless function create --name aiAdvisor
yc serverless function version create ...
```

## Переменные окружения через Lockbox
Перечисли все секреты которые нужно создать в Lockbox:
- YANDEXGPT_API_KEY
- YANDEXGPT_FOLDER_ID
- GIGACHAT_CLIENT_ID
- GIGACHAT_CLIENT_SECRET
- APP_CHECK_PROJECT_ID

## Бесплатные квоты (укажи актуальные цифры)
- Yandex Cloud Functions: ? вызовов/месяц бесплатно
- YandexGPT бесплатный тариф: ? RPM, ? токенов/месяц
- GigaChat бесплатный тариф: ? запросов/день

## Мониторинг
Добавь метрики в Yandex Cloud Monitoring:
- ai_request_total (counter, labels: provider, status)
- ai_latency_ms (histogram, labels: provider)
- fallback_triggered (counter, labels: from_provider, to_provider)
