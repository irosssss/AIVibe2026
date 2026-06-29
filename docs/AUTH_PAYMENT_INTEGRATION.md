# Авторизация и оплата веб-кабинета — интеграция (2026-06)

> Как «оживить» вход (Яндекс ID / VK ID) и подписку (ЮKassa) в веб-кабинете.
> Код-каркас уже есть: `backend/functions/web-billing/index.js` (рабочий стаб,
> читает секреты из env) + хук `AIVibeAPI.billing` в `web/mock.js`.
>
> **Главное честно:** «живым» это станет только после того, как **владелец**
> зарегистрирует приложения и магазин и положит секреты в окружение. Секреты
> **нельзя** коммитить в публичный репозиторий и **нельзя** класть в клиентский
> JS — только server-side (env Cloud Function / Yandex Lockbox). До настройки
> эндпоинты честно отвечают `503 not-configured`.

## 1. Чек-лист владельца (что зарегистрировать)

| Сервис | Где | Что получить |
|---|---|---|
| **Яндекс ID (OAuth)** | oauth.yandex.ru → создать приложение | `client_id`, `client_secret`; redirect URI = `https://<домен>/auth/yandex/callback`; права: `login:email`, `login:info` |
| **VK ID** | id.vk.com → создать приложение | `client_id` (+ VK ID SDK на фронте, OAuth 2.1 + PKCE) |
| **ЮKassa** | yookassa.ru → магазин | `shopId`, `secretKey`; настроить webhook на `https://<домен>/billing/webhook` (события `payment.succeeded`) |

ИП у владельца есть (нужен для договора ЮKassa). Apple IAP не используем — оплата на вебе.

## 2. Переменные окружения (server-side)

Кладутся в окружение Cloud Function `web-billing` (или в Yandex Lockbox):
```
YANDEX_OAUTH_CLIENT_ID=...
YANDEX_OAUTH_CLIENT_SECRET=...
VK_OAUTH_CLIENT_ID=...
YOOKASSA_SHOP_ID=...
YOOKASSA_SECRET_KEY=...
WEB_RETURN_URL=https://<домен>/cabinet?paid=1
```

## 3. Эндпоинты (уже в стабе)

| Метод · путь | Что делает |
|---|---|
| `POST /billing/create` `{ userId, plan }` | создаёт платёж ЮKassa, возвращает `confirmationUrl` (редирект на оплату) |
| `POST /billing/webhook` | принимает уведомление ЮKassa, **перепроверяет** статус платежа в API (не доверяет телу), отмечает подписку |
| `GET /auth/yandex/callback?code=` | обмен кода на токен + профиль Яндекс ID |
| `GET /auth/vk/callback` | заглушка — VK ID идёт через SDK (PKCE), реализуется при подключении |

Тарифы заданы в стабе: `pro_month = 1490 ₽`, `pro_year = 12900 ₽` (поправить под экономику).

## 4. Как это связано с вебом (точки замены мока)

В `web/mock.js` сигнатуры уже под реальный бэкенд:
- `AIVibeAPI.auth.loginWithYandex/VK` → редирект на OAuth-провайдера → `/auth/*/callback` → сессия.
- `AIVibeAPI.billing.createPayment({ plan })` → `POST /billing/create` → редирект на `confirmationUrl`.

Сейчас `billing.createPayment` возвращает честный плейсхолдер `not-configured` — UI показывает «оплата подключится после регистрации ЮKassa», а не имитирует успешную оплату.

## 5. Что осталось доделать кодом (после регистрации аккаунтов)

1. **Сессии:** в `/auth/yandex/callback` — создать/найти пользователя в YDB, выдать сессионный JWT (Set-Cookie), редирект на `WEB_RETURN_URL`. (помечено `TODO(session)`)
2. **Хранение подписки:** в `/billing/webhook` — записать активную подписку в YDB (`userId`, `plan`, дата окончания). (`TODO(persist)`)
3. **VK ID:** подключить VK ID SDK на фронте (PKCE), верифицировать `id_token` на бэкенде.
4. **UI «Тарифы»:** экран выбора подписки в кабинете с кнопкой → `billing.createPayment` → редирект на оплату. (мок-хук готов, экран — небольшой следующий шаг)
5. **Деплой:** `web-billing` как отдельная Cloud Function (как остальные в `backend/functions/`), секреты — в env/Lockbox.

## 6. Связанные документы
- `WEB_PROTOTYPE_2026-06.md` — веб-слой и общий план оживления.
- `audit-2026-05-monetization` (память) — freemium+подписка, оплата на сайте, ЮKassa, контур пользователя.
