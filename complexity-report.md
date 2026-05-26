# Code Complexity Report

Generated: 2026-05-26T07:26:23.471Z
Script: `scripts/code-complexity-analyzer.mjs`

## Сводка

- ✅ OK: 6
- ⚠️  WARN: 1
- ⏭  Skipped (файлы не найдены): 0

## Проверки

| # | Проверка | Статус |
|---|----------|--------|
| 1 | Circuit Breaker constants sync | ✅ OK |
| 2 | Multi-pass parsing | ✅ OK |
| 3 | Backend entry points use shared fallback | ✅ OK |
| 4 | RAG indexer N+1 | ✅ OK |
| 5 | RAG search full scan | ⚠️ WARN |
| 6 | Analytics event loss | ✅ OK |
| 7 | Retry-After handling | ✅ OK |

## Топ-8 файлов по размеру

| Размер | Путь |
|--------|------|
| 47.5 KB | `AIVibeTests/AI/Integration/AgentIntegrationTests.swift` |
| 41.1 KB | `AIVibeTests/AI/AgentLoopTests.swift` |
| 35.2 KB | `AIVibe/Core/AI/ToolRegistry/Tools/GenerateArrangementTool.swift` |
| 28.5 KB | `AIVibe/Core/AI/ToolRegistry/Tools/RecommendStyleTool.swift` |
| 27.1 KB | `AIVibe/Core/AI/Agent/AgentLoop.swift` |
| 25.9 KB | `AIVibe/Core/AI/Agent/AgentObservability.swift` |
| 22.8 KB | `AIVibe/Core/AI/Agent/ContextBuilder.swift` |
| 19.8 KB | `AIVibe/Core/AI/ToolRegistry/Tools/DraftShoppingListTool.swift` |

---

Запуск: `node scripts/code-complexity-analyzer.mjs`
При наличии WARN скрипт завершается с exit code 1 — можно использовать как CI gate.
