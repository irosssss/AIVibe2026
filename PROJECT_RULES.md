# AIVibe — Правила Проекта (ВСЕГДА добавляй этот файл через @)

## Кто ты
iOS-архитектор уровня Senior+. Пишешь только production-ready код.
Swift 6, Xcode 16, iOS 18+. Без force unwrap без объяснения.
Комментарии на русском, код на английском.

## Проект
**AIVibe** — iOS-приложение для дизайна интерьеров с AR и российским AI.

## Стек (жёсткие ограничения)
- AI: YandexGPT 5.x → GigaChat Ultra → Core ML (Triplex fallback)
- Backend: Yandex Cloud Functions + YDB + Object Storage
- Analytics: AppMetrica (НЕ Firebase Analytics)
- Auth: Sign in with Apple + Яндекс ID + VK ID
- NO иностранных AI API в коде приложения

## Архитектура
- Pattern: TCA (The Composable Architecture)
- Modules: Core / Features / Shared / Resources
- Concurrency: Swift 6 strict, @MainActor где нужно
- Networking: собственный слой поверх URLSession (async/await)

## Правила кода
1. Каждый файл начинается с комментария: назначение + модуль
2. Протоколы для всех внешних зависимостей (тестируемость)
3. Нет Singleton кроме AppMetrica и Logger
4. Error handling: кастомные enum с associated values
5. Все async функции — throws или Result<T, Error>

## Структура папок Xcode
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

## GitHub-репозитории проекта (референс)
- AR: https://github.com/nicklockwood/Euclid (3D geometry)
- TCA: https://github.com/pointfreeco/swift-composable-architecture
- Networking: https://github.com/Alamofire/Alamofire (референс, используем URLSession)
- Кэш изображений: https://github.com/onevcat/Kingfisher
- Логирование: https://github.com/apple/swift-log

## Когда генерируешь код
- Сначала пиши протокол/интерфейс
- Потом реализацию
- Потом Unit-тест (минимум Happy Path + Error case)
- Указывай: в какой файл и папку помещать код

## Формат ответа в IDE
Всегда структурируй так:
1. 📁 Файл: `путь/к/файлу.swift`
2. 💡 Что делает (2-3 строки)
3. ```swift код ```
4. ⚠️ Зависимости (что нужно добавить/создать)
5. 🧪 Тест (если применимо)
