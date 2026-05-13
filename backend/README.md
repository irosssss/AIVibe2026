# AIVibe Backend — Yandex Cloud Function

AI Advisor proxy с Triplex Fallback: **YandexGPT → GigaChat → Cache**.

## Архитектура

```
[iOS Client] ──POST──▶ [Yandex API Gateway] ──▶ [Yandex Cloud Function]
                                                       │
                                          ┌────────────┼────────────┐
                                          ▼            ▼            ▼
                                      YandexGPT    GigaChat     Cache
                                                      ⚠️
                                          Самоподписанный сертификат
```

## Файлы

| Файл | Назначение |
|---|---|
| `index.js` | Точка входа. Разбор запроса, rate limit, triplex fallback, логирование |
| `yandexgpt.js` | Клиент YandexGPT Foundation Models API |
| `gigachat.js` | Клиент GigaChat Chat Completions API + OAuth |
| `cache.js` | In-memory кэш (50 записей, TTL 1 час) |
| `package.json` | Зависимости (нет внешних — только встроенный fetch) |

## Переменные окружения

| Переменная | Описание |
|---|---|
| `YANDEX_IAM_TOKEN` | IAM-токен для YandexGPT (обновлять каждые 12 ч) |
| `YANDEX_FOLDER_ID` | ID каталога Yandex Cloud |
| `GIGACHAT_CLIENT_SECRET` | Секретный ключ GigaChat |
| `APP_TOKEN` | Опциональный токен для проверки X-App-Token |

## Деплой через Yandex CLI

```bash
# 1. Создать функцию
yc serverless function create --name aivibe-ai-advisor

# 2. Создать версию
yc serverless function version create \
  --function-name aivibe-ai-advisor \
  --runtime nodejs20 \
  --entrypoint index.handler \
  --memory 256m \
  --execution-timeout 30s \
  --environment \
    YANDEX_IAM_TOKEN=<token>,\
    YANDEX_FOLDER_ID=<folder-id>,\
    GIGACHAT_CLIENT_SECRET=<secret>,\
    APP_TOKEN=<token> \
  --source-path ./backend.zip

# 3. Вызвать тестовый запрос
yc serverless function invoke aivibe-ai-advisor \
  -d '{"body": "{\"prompt\":\"Дизайн интерьера гостиной\", \"userId\":\"test-1\"}"}'
```

## Rate Limiting

- **20 запросов в минуту** на один `userId`
- Сброс каждые 60 секунд
- In-memory (сбрасывается при перезапуске функции)

## Бесплатные квоты Yandex Cloud (на момент написания)

| Сервис | Бесплатный лимит |
|---|---|
| Yandex Cloud Functions | 1 млн вызовов/месяц |
| YandexGPT | 1 млн токенов/месяц, 20 RPM |
| GigaChat | 120 запросов/день (бесплатный тариф) |

## Мониторинг

Логи автоматически собираются Yandex Cloud Logging.
Рекомендуется подключить Yandex Cloud Monitoring с метриками:
- `ai_request_total` (labels: provider, status)
- `ai_latency_ms` (histogram, labels: provider)
- `fallback_triggered` (labels: from_provider, to_provider)

## ⚠️ Безопасность

- Никогда не хардкодьте API-ключи в коде
- Используйте **Yandex Lockbox** для хранения секретов в продакшне
- GigaChat использует самоподписанный сертификат — **только для разработки**
- В продакшне — pinned certificate или прокси через Yandex API Gateway
