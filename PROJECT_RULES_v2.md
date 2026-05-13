# AIVibe — PROJECT RULES
# Добавляй этот файл через @ в КАЖДЫЙ запрос к DeepSeek

## 🤖 Модель и IDE
IDE: Polza IDE | Модель: DeepSeek V4 Flash | ОС: Windows 11
Путь проекта: C:\Users\poddu\Documents\AIVIBE2026
GitHub: https://github.com/irosssss/AIVibe2026

## 📱 Проект
AIVibe — iOS-приложение дизайна интерьеров с AR и российским AI.
Платформа: iOS 18+ | Swift 6 | Xcode 16

## 🏗️ Архитектура
Pattern: TCA (The Composable Architecture)
Concurrency: Swift 6 strict — actor, @Sendable, @MainActor
NO: force unwrap, implicitly unwrapped optionals без объяснения
NO: @unchecked Sendable без комментария почему

## 🤖 AI Stack (строго в этом порядке)
1. YandexGPT 5 Pro → основной
2. GigaChat Ultra  → резервный  
3. CoreML offline  → оффлайн fallback
Circuit Breaker: 3 ошибки → пауза 5 минут

## 🗂️ Структура файлов Xcode
AIVibe/
├── App/
├── Core/
│   ├── AI/          ← AIProviderRouter, CircuitBreaker, Providers/
│   ├── Network/     ← NetworkClient, NetworkError
│   ├── Storage/     ← StorageClient
│   └── Analytics/   ← AppMetricaAnalytics
├── Features/
│   ├── RoomScan/    ← ждёт Mac
│   ├── ARDesigner/  ← ждёт Mac
│   ├── AIAdvisor/   ← ждёт Mac
│   ├── Portfolio/   ← ждёт Mac
│   └── Marketplace/ ← ждёт Mac
└── Shared/
    ├── UI/
    ├── Utils/       ← Logger.swift уже есть
    └── Models/
backend/             ← Yandex Cloud Functions (Node.js 20)
AIVibeTests/AI/      ← Unit тесты

## ✅ Уже готово (НЕ пересоздавай)
- AIVibe/Core/AI/AIError.swift         (12 case-ов)
- AIVibe/Core/AI/AIProvider.swift      (протокол AIProviderProtocol)
- AIVibe/Core/AI/AIModels.swift        (AIPrompt, AIResponse, ChatMessage)
- AIVibe/Core/AI/CircuitBreaker.swift  (actor, threshold=3, timeout=300s)
- AIVibe/Core/AI/AIProviderRouter.swift (actor, Triplex fallback)
- AIVibe/Core/Storage/StorageClient.swift
- AIVibe/Core/Analytics/AppMetricaWrapper.swift
- AIVibe/Core/Network/NetworkClient.swift

## 📋 Правила кода
1. Каждый файл начинается с комментария: // путь/к/файлу.swift — назначение
2. Протоколы для всех внешних зависимостей
3. Ошибки — кастомные enum, никогда не глотать
4. Комментарии на русском, идентификаторы на английском
5. Один файл = одна ответственность

## 💻 Создание файлов (Windows PowerShell)
Всегда создавай файлы через терминал:
New-Item -ItemType File -Force -Path "путь\к\файлу.swift"
После создания контент через Set-Content или Out-File -Encoding UTF8

## 📤 Коммит после каждой сессии
git add .
git commit -m "feat: описание"
git push origin master

## 🔑 Секреты — НИКОГДА в коде
API ключи только через:
- iOS: Environment/DI через init параметры
- Backend: Yandex Lockbox или process.env

## 📦 SPM зависимости (Package.swift уже настроен)
- swift-composable-architecture (TCA)
- Kingfisher (кэш изображений)
- swift-log (логирование)
- swift-collections
