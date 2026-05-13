# AIVibe

iOS-приложение для дизайна интерьеров с AR и российским AI.

---

## 🚀 Что умеет AIVibe

- 📡 **LiDAR сканирование** — RoomPlan 2 создаёт точную 3D-модель комнаты
- 🤖 **Российский AI** — YandexGPT 5 анализирует интерьер, GigaChat как резерв
- 🪄 **AR дизайнер** — RealityKit 4, расставляй мебель через камеру
- 🛒 **Маркетплейсы РФ** — товары с Wildberries, Ozon, СберМегаМаркет
- 📵 **Оффлайн-режим** — Core ML работает без интернета
- 🗂 **Портфолио** — публичные ссылки на AR-проекты

---

## 🛠️ Стек

| Слой | Технология |
|------|-----------|
| Платформа | iOS 18+, Swift 6, Xcode 16 |
| Архитектура | TCA (The Composable Architecture) |
| AR | RoomPlan 2 + RealityKit 4 + LiDAR |
| AI (основной) | YandexGPT 5 Pro |
| AI (резервный) | GigaChat Ultra |
| AI (оффлайн) | Core ML ONNX |
| Backend | Yandex Cloud Functions + YDB |
| Аналитика | AppMetrica |
| Auth | Sign in with Apple + Яндекс ID + VK ID |
| CI/CD | GitHub Actions + Fastlane |

---

## 📊 Текущее состояние (май 2026)

```
✅ Core/AI Layer
   ├── AIError.swift          (12 типов ошибок)
   ├── AIProvider.swift       (протокол)
   ├── AIModels.swift         (AIPrompt, AIResponse, ChatMessage)
   ├── CircuitBreaker.swift   (защита от лавинных сбоев)
   ├── AIProviderRouter.swift (Triplex fallback)
   └── Providers/
       ├── YandexGPTProvider  🔄
       ├── GigaChatProvider   🔄
       └── CoreMLProvider     🔄

✅ Core/Network    (NetworkClient)
✅ Core/Storage    (StorageClient)
✅ Core/Analytics  (AppMetrica wrapper)
✅ CI/CD           (GitHub Actions + Fastlane)
✅ Backend         🔄 (Yandex Cloud Function)

🍎 Features        (ждёт Mac + Xcode)
   ├── RoomScan    (RoomPlan 2, LiDAR)
   ├── ARDesigner  (RealityKit 4)
   ├── AIAdvisor   (чат с AI)
   ├── Portfolio
   └── Marketplace
```

---

## 🏁 Быстрый старт

### Требования
- Xcode 16+
- Swift 6
- macOS 14+ (для разработки iOS)
- Yandex Cloud аккаунт (для AI backend)

### Установка

```bash
git clone https://github.com/irosssss/AIVibe2026.git
cd AIVibe2026
swift package resolve
open AIVibe.xcodeproj
```

### Переменные окружения (backend)

Создай в Yandex Lockbox:
```
YANDEX_IAM_TOKEN      — IAM токен Yandex Cloud
YANDEX_FOLDER_ID      — ID папки в Yandex Cloud
GIGACHAT_CLIENT_SECRET — секрет клиента GigaChat
```

### CI/CD

```bash
bundle exec fastlane test    # тесты
bundle exec fastlane beta    # TestFlight
```

---

## 🤖 AI Fallback схема

```
Запрос → YandexGPT 5 Pro
           ↓ (ошибка или timeout 25с)
         GigaChat Ultra
           ↓ (ошибка или timeout 25с)
         Core ML (оффлайн)
           ↓ (ошибка)
         AIError.allProvidersExhausted
```

Circuit Breaker: после 3 ошибок подряд провайдер пропускается 5 минут.

---

## 📅 Roadmap

| Неделя | Задача | Статус |
|--------|--------|--------|
| 1 | Структура, CI/CD | ✅ |
| 2 | Core/AI Router | ✅ |
| 2-3 | AI Providers, Backend | 🔄 |
| 3 | RoomScan (Mac) | ⏳ |
| 4 | AR Designer (Mac) | ⏳ |
| 5 | UI + Auth (Mac) | ⏳ |
| 6 | Marketplace (Mac) | ⏳ |
| 7 | Тестирование (Mac) | ⏳ |
| 8 | TestFlight + App Store | ⏳ |

---

## 📝 Разработка на Windows

Текущий этап (Core + Backend) разрабатывается на Windows через Polza IDE + DeepSeek V4 Flash.

Для Features (AR, RoomScan, UI) необходим Mac с Xcode 16+.

Компиляция и тесты — через GitHub Actions macos-14 runner.

---

## 📄 Лицензия

© 2026 AIVibe. Все права защищены.
