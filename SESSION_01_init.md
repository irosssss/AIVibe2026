# СЕССИЯ 1 — Инициализация Проекта

> Вставляй этот промпт в Polza IDE в режиме Agent
> Обязательно добавь @PROJECT_RULES.md в контекст перед отправкой

---

Создай структуру Xcode-проекта AIVibe с нуля.

## Задача
Сгенерируй все файлы-заглушки для полной структуры проекта AIVibe согласно
PROJECT_RULES.md. Используй Agent-режим чтобы создать файлы прямо в папке проекта.

## Что создать

### 1. Package.swift (SPM зависимости)
Включи:
- swift-composable-architecture (pointfreeco/swift-composable-architecture)
- Kingfisher (onevcat/Kingfisher) — кэш изображений
- swift-log (apple/swift-log) — логирование
- AppMetrica SDK — через SPM если доступен, иначе укажи инструкцию
- swift-collections (apple/swift-collections)

### 2. Структура папок
Создай все папки согласно структуре из PROJECT_RULES.md.
В каждой папке — пустой `.gitkeep` или минимальный `.swift` файл с TODO.

### 3. Конфиг-файлы
- `.gitignore` для iOS-проекта (включи: Pods/, .DS_Store, *.xcuserstate,
  xcuserdata/, DerivedData/, .env, Secrets.plist)
- `README.md` с описанием проекта и инструкцией по запуску
- `.swiftlint.yml` с правилами для Swift 6

### 4. GitHub Actions (CI/CD)
Файл: `.github/workflows/ios.yml`
- Триггер: push в main и pull_request
- Jobs: SwiftLint → Build → Test
- Использует: macos-14 runner (бесплатный)
- Кэширует: SPM пакеты

### 5. Fastlane
- `Fastfile` с lanes: `test`, `beta` (TestFlight)
- `Matchfile` (пустой шаблон с комментариями)
- `Appfile` с bundle ID: `ru.aivibe.app`

## Формат вывода
Для каждого файла:
📁 Полный путь
📄 Полное содержимое файла
Затем создай файл через терминал (Agent mode).

## После создания структуры
Напиши команду для инициализации git-репозитория и первого коммита.
