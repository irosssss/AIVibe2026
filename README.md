# AIVibe

iOS-приложение для дизайна интерьеров с AR и российским AI.

## Стек

- **Платформа:** iOS 18+
- **Архитектура:** TCA (The Composable Architecture)
- **AI:** YandexGPT 5.x → GigaChat Ultra → Core ML (Triplex fallback)
- **Бэкенд:** Yandex Cloud Functions + YDB + Object Storage
- **Аналитика:** AppMetrica
- **Авторизация:** Sign in with Apple + Яндекс ID + VK ID

## Структура проекта

```
AIVibe/
├── App/                    # AppDelegate, SceneDelegate, DI
├── Core/
│   ├── Network/            # URLSession wrapper, interceptors
│   ├── AI/                 # AIProviderRouter, провайдеры
│   ├── Storage/            # YDB client, кэш
│   └── Analytics/          # AppMetrica wrapper
├── Features/
│   ├── RoomScan/           # RoomPlan, StructureBuilder
│   ├── ARDesigner/         # RealityKit, RealityView
│   ├── AIAdvisor/          # Чат с AI, рекомендации
│   ├── Portfolio/          # Портфолио дизайнеров
│   └── Marketplace/        # Wildberries/Ozon интеграция
└── Shared/
    ├── UI/                 # DesignSystem, компоненты
    ├── Utils/              # Extensions, helpers
    └── Models/             # Shared data models
```

## Установка и запуск

### Предварительные требования

- Xcode 16+
- Swift 6
- iOS 18+
- CocoaPods (для AppMetrica SDK)

### Шаги

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/nicklockwood/AIVibe.git
   cd AIVibe
   ```

2. Установите Swift Package Manager зависимости:
   ```bash
   swift package resolve
   ```

3. Откройте проект в Xcode:
   ```bash
   open AIVibe.xcodeproj
   ```

4. **AppMetrica SDK:** Скачайте бинарный SDK из личного кабинета Яндекс Cloud и добавьте в проект вручную.

5. Соберите и запустите проект (`Cmd + R`).

### CI/CD

```bash
# Запуск линтера
bundle exec fastlane lint

# Запуск тестов
bundle exec fastlane test

# Сборка для TestFlight
bundle exec fastlane beta
```

## Лицензия

© 2024 AIVibe. Все права защищены.
