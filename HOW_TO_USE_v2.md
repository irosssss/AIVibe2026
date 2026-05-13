# HOW TO USE — AIVibe2026
# Инструкция по работе в Polza IDE с DeepSeek V4 Flash

---

## 🎯 Правило номер один
**Один промпт = одна задача = один файл**
DeepSeek теряет контекст при больших задачах.
Дождись выполнения → проверь файл → следующий промпт.

---

## 📁 Файлы системы
| Файл | Когда использовать |
|------|-------------------|
| PROJECT_RULES.md | @ в КАЖДОМ запросе — обязательно |
| DEEPSEEK_PROMPTS.md | Готовые промпты по сессиям |
| SESSION_01_init.md | ✅ Выполнено |
| SESSION_02_ai_router.md | ✅ Выполнено |
| SESSION_03_ar_roomscan.md | Ждёт Mac |
| SESSION_04_backend.md | Используй промпт из DEEPSEEK_PROMPTS.md |

---

## 🔄 Рабочий процесс

### Каждый запрос:
```
@PROJECT_RULES.md @нужный_файл.swift

[промпт из DEEPSEEK_PROMPTS.md]
```

### После каждой сессии:
```powershell
cd C:\Users\poddu\Documents\AIVIBE2026
git add .
git commit -m "feat: название"
git push origin master
```

---

## ✅ Текущий статус (май 2026)

### Готово (Windows) ✅
- [x] Структура проекта
- [x] CI/CD (GitHub Actions + Fastlane)
- [x] Core/AI — AIError, AIProvider, AIModels
- [x] Core/AI — CircuitBreaker, AIProviderRouter
- [x] Core/Storage — StorageClient
- [x] Core/Analytics — AppMetricaWrapper
- [x] Core/Network — NetworkClient

### В работе (Windows) 🔄
- [ ] Core/AI/Providers — YandexGPT, GigaChat, CoreML
- [ ] AIVibeTests — тесты роутера
- [ ] backend/ — Yandex Cloud Function

### Ждёт Mac 🍎
- [ ] Features/RoomScan (RoomPlan 2, LiDAR)
- [ ] Features/ARDesigner (RealityKit 4)
- [ ] Features/AIAdvisor (UI чат)
- [ ] Features/Portfolio
- [ ] Features/Marketplace

---

## ⚠️ Частые ошибки

**Ошибка:** "No local changes" в GitHub Desktop
**Решение:** File → Add Existing Repository → C:\Users\poddu\Documents\AIVIBE2026

**Ошибка:** Connection error в Polza
**Решение:** Подожди 2-3 минуты, повтори запрос. НЕ меняй модель.

**Ошибка:** Файл создан в Desktop\AIVIBE 1 вместо Documents\AIVIBE2026
**Решение:** Всегда проверяй путь в терминале: `pwd`

**Ошибка:** Модель сменилась сама
**Решение:** Верни DeepSeek V4 Flash. Для сложного кода — Claude Sonnet 4.6

---

## 🚀 Следующие шаги

1. Запусти СЕССИЮ 3 из DEEPSEEK_PROMPTS.md → YandexGPTProvider
2. Запусти СЕССИЮ 4 → GigaChatProvider  
3. Запусти СЕССИЮ 5 → CoreMLProvider
4. Запусти СЕССИЮ 6 → NetworkClient (если ещё не готов)
5. Запусти СЕССИЮ 8 → Тесты
6. Запусти СЕССИЮ 9 → Backend
7. Сделай финальный коммит
8. Получи Mac → начинай Features
