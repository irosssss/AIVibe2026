# Code Complexity Report

Generated: 2026-06-10T07:24:25.599Z
Script: `scripts/code-complexity-analyzer.mjs`

## Сводка

- ✅ OK: 7
- ⚠️  WARN: 0
- ⏭  Skipped (файлы не найдены): 0

## Проверки

| # | Проверка | Статус |
|---|----------|--------|
| 1 | Circuit Breaker constants sync | ✅ OK |
| 2 | Multi-pass parsing | ✅ OK |
| 3 | Backend entry points use shared fallback | ✅ OK |
| 4 | RAG indexer N+1 | ✅ OK |
| 5 | RAG search full scan | ✅ OK |
| 6 | Analytics event loss | ✅ OK |
| 7 | Retry-After handling | ✅ OK |

## Топ-8 файлов по размеру

| Размер | Путь |
|--------|------|
| 47.4 KB | `AIVibeTests/AI/Integration/AgentIntegrationTests.swift` |
| 40.7 KB | `AIVibeTests/AI/AgentLoopTests.swift` |
| 35.4 KB | `AIVibe/Core/AI/ToolRegistry/Tools/GenerateArrangementTool.swift` |
| 34.9 KB | `AIVibe/Features/RoomScan/RoomScanFlowView.swift` |
| 28.7 KB | `AIVibe/Core/AI/ToolRegistry/Tools/RecommendStyleTool.swift` |
| 27.7 KB | `AIVibe/Core/AI/Agent/AgentLoop.swift` |
| 26.4 KB | `AIVibe/Core/AI/Agent/AgentObservability.swift` |
| 25.5 KB | `AIVibe/Core/AI/Agent/ContextBuilder.swift` |

---

Запуск: `node scripts/code-complexity-analyzer.mjs`
При наличии WARN скрипт завершается с exit code 1 — можно использовать как CI gate.
