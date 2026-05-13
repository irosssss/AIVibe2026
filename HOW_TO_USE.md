# КАК РАБОТАТЬ С ЭТОЙ СИСТЕМОЙ В POLZA IDE

## Структура файлов
```
AIVIBE 1/
├── PROJECT_RULES.md        ← ВСЕГДА добавляй через @
├── SESSION_01_init.md      ← Неделя 1: структура проекта
├── SESSION_02_ai_router.md ← Неделя 1-2: AI Router
├── SESSION_03_ar_roomscan.md ← Неделя 2-3: AR модуль
├── SESSION_04_backend.md   ← Неделя 2: Backend
└── (создавай новые по мере необходимости)
```

---

## Пошаговый воркфлоу

### Шаг 1 — Скопируй эти файлы в папку AIVIBE 1
Положи все .md файлы в корень проекта.

### Шаг 2 — Начни с SESSION_01
В чате Polza IDE:
```
@PROJECT_RULES.md @SESSION_01_init.md

Выполни задачи из SESSION_01. 
Начни с Package.swift и структуры папок.
```

### Шаг 3 — Для каждой следующей сессии
```
@PROJECT_RULES.md @SESSION_02_ai_router.md

Реализуй AIProviderRouter. 
Начни с протокола AIProvider.
```

### Шаг 4 — При работе над конкретным файлом
```
@PROJECT_RULES.md @Core/AI/AIProvider.swift

Добавь поддержку streaming через AsyncStream.
Соблюдай все правила из PROJECT_RULES.
```

---

## Полезные slash-команды (если поддерживает Polza)
- `/new` — новый файл
- `/edit` — редактировать существующий
- `/explain` — объяснить код

---

## Правило работы с Qwen 3 35B A3B

### ✅ Хорошие запросы (модель справится отлично):
- "Напиши протокол AIProvider в Swift 6"
- "Создай Unit-тест для AIProviderRouter"
- "Оптимизируй этот код для Swift 6 concurrency"
- "Объясни этот RealityKit код"

### ⚠️ Проверяй руками:
- Конкретные endpoint'ы YandexGPT/GigaChat (могли измениться)
- Версии API (модель может знать устаревшие)
- Квоты бесплатных тарифов (проверяй на сайте)

### ❌ Не доверяй без проверки:
- "Актуальный" формат IAM-токена Yandex
- Конкретные имена моделей GigaChat (обновляются часто)
- App Store Connect API изменения 2026

---

## 🚨 Напоминание: нужен Mac для iOS-разработки
Текущая машина: Windows (PowerShell)

**Что можно делать сейчас на Windows:**
- ✅ Планировать архитектуру
- ✅ Писать Swift-код в Polza IDE
- ✅ Настраивать backend (Yandex Cloud)
- ✅ Создавать CI/CD конфиги
- ✅ Изучать документацию

**Что нужен Mac:**
- ❌ Запустить Xcode
- ❌ Сборка .ipa
- ❌ Тестирование на симуляторе/устройстве
- ❌ TestFlight / App Store публикация

**Временное решение:** GitHub Actions с macos-14 runner
для компиляции и проверки кода без локального Mac.

---

## Roadmap первых 8 недель

| Неделя | Что делать | Нужен Mac? |
|--------|-----------|------------|
| 1 | Структура проекта, Package.swift, CI/CD | Нет |
| 2 | AI Router, Backend Cloud Function | Нет |
| 3 | RoomScan, ImagePreprocessor | **Да** |
| 4 | AR Designer, RealityView | **Да** |
| 5 | UI/UX, основные экраны | **Да** |
| 6 | Marketplace интеграция | **Да** |
| 7 | Тестирование, баги | **Да** |
| 8 | TestFlight beta, аналитика | **Да** |
