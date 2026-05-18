// AIVibe/Core/AI/ToolRegistry/ResultLimiter.swift
// Этап 3: Ограничитель размера результатов.
// Обрезает/суммирует tool results, превышающие maxChars.
// Blueprint §5: max_result_chars_per_tool = 8000.

import Foundation

// MARK: - Result Limiter

/// Ограничивает размер результата выполнения инструмента.
///
/// Правила:
/// - Результат ≤ maxChars → возвращается как есть.
/// - Результат > maxChars → обрезается с суффиксом-предупреждением.
/// - JSON-результаты обрезаются до ближайшего целого JSON-токена.
///
/// Blueprint §5: maxResultChars = 8000 по умолчанию.
public struct ResultLimiter: Sendable {

    /// Максимальное количество символов.
    public let maxChars: Int

    public init(maxChars: Int = 8000) {
        self.maxChars = maxChars
    }

    // MARK: - Public API

    /// Применяет лимит к результату.
    ///
    /// - Returns: `ToolResult` с статусом `.success` (если уложились) или `.truncated`.
    public func enforce(_ result: ToolResult) -> ToolResult {
        guard result.data.count > maxChars else {
            return result
        }

        // Пытаемся умно обрезать JSON
        let truncated: String
        if isJSON(result.data) {
            truncated = trimJSON(result.data) + "\n\n⚠️ [Результат обрезан: \(result.data.count) → \(maxChars) символов]"
        } else {
            let cutIndex = result.data.prefix(maxChars).lastIndex(where: { $0 == "\n" || $0 == "." })
                ?? result.data.index(result.data.startIndex, offsetBy: min(maxChars, result.data.count))
            truncated = String(result.data[..<cutIndex])
                + "\n\n⚠️ [Результат обрезан. Оригинальный размер: \(result.data.count) символов. " +
                "Запросите более узкий поиск или используйте пагинацию.]"
        }

        return ToolResult(
            callId: result.callId,
            toolName: result.toolName,
            status: .truncated,
            data: truncated,
            durationMs: result.durationMs,
            resultSize: result.data.count
        )
    }

    /// Применяет лимит к сырой строке (для использования внутри инструментов).
    public func enforceString(
        _ text: String,
        callId: UUID = UUID(),
        toolName: String = "unknown",
        durationMs: Double = 0
    ) -> ToolResult {
        let result = ToolResult(
            callId: callId,
            toolName: toolName,
            status: .success,
            data: text,
            durationMs: durationMs
        )
        return enforce(result)
    }

    // MARK: - Private

    private func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    /// Обрезает JSON до последнего валидного токена.
    private func trimJSON(_ text: String) -> String {
        let maxIndex = text.index(
            text.startIndex,
            offsetBy: min(maxChars - 80, text.count),
            limitedBy: text.endIndex
        ) ?? text.endIndex

        // Ищем последнюю запятую или закрывающую скобку
        let prefix = String(text[..<maxIndex])
        if let lastComma = prefix.lastIndex(of: ",") {
            return String(text[..<lastComma]) + "\n  ..."
        }
        if let lastBrace = prefix.lastIndex(of: "}") {
            return String(text[..<lastBrace]) + "}"
        }

        return String(prefix)
    }
}

// MARK: - Result Trimmer (для session-уровня)

/// Суммирует/сжимает результаты предыдущих шагов для укладки в контекстное окно.
/// Blueprint §9: Auto-compaction при 80% контекстного окна.
public struct ResultTrimmer: Sendable {

    /// Максимальная сумма всех tool results в промпте (символов).
    public let maxTotalChars: Int

    public init(maxTotalChars: Int = 12_000) {
        self.maxTotalChars = maxTotalChars
    }

    // MARK: - Public API

    /// Сжимает массив результатов до суммарного размера ≤ maxTotalChars.
    ///
    /// Стратегия:
    /// 1. Последние 2 результата — полные (recent context).
    /// 2. Предыдущие — сжатые до summary (первые 200 символов + размер).
    /// 3. Ошибки — сохраняются полностью (важны для диагностики).
    ///
    /// - Returns: Сжатый массив результатов.
    public func trim(_ results: [ToolResult]) -> [ToolResult] {
        let totalChars = results.reduce(0) { $0 + $1.data.count }
        guard totalChars > maxTotalChars else {
            return results
        }

        // Сохраняем последние 2 результата полностью
        let keepFull = min(2, results.count)
        let recent = results.suffix(keepFull)
        let older = results.dropLast(keepFull)

        let truncatedOlder: [ToolResult] = older.map { result in
            // Ошибки сохраняем полностью
            if result.status != .success {
                return result
            }
            // Успешные — сжимаем до первых 200 символов
            let preview = String(result.data.prefix(200))
            return ToolResult(
                callId: result.callId,
                toolName: result.toolName,
                status: .truncated,
                data: preview + "\n… [сжато: \(result.data.count) символов]",
                durationMs: result.durationMs,
                resultSize: result.data.count
            )
        }

        return Array(truncatedOlder + recent)
    }
}
