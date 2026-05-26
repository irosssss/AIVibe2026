// AIVibe/Core/AI/ToolRegistry/ToolScheduler.swift
// Этап 4: Планировщик вызовов инструментов.
// Определяет порядок выполнения tool calls:
// - Разрешает зависимости (один tool call зависит от выхода другого)
// - Параллельные вызовы для независимых инструментов
// - Последовательные — для readPrivate → draft → action цепочек

import Foundation
import Logging

// MARK: - Tool Scheduler

/// Планировщик порядка выполнения tool calls.
///
/// Blueprint §4: `scheduler.order(model_output.tool_calls)`
///
/// Правила упорядочивания:
/// 1. Сначала readPublic — быстрые, независимые запросы (параллельно).
/// 2. Затем readPrivate — требуют данных пользователя (параллельно).
/// 3. Затем draft — создание рекомендаций на основе чтения (последовательно).
/// 4. Последними action — внешние эффекты (последовательно, с одобрениями).
///
/// Внутри одной группы: параллельно если нет явных зависимостей.
public struct ToolScheduler: Sendable {
    private let logger = Logger(label: "ai.tool-scheduler")

    public init() {}

    // MARK: - Public API

    /// Упорядочивает массив tool calls в оптимальном порядке выполнения.
    ///
    /// - Parameter calls: Tool calls из model output.
    /// - Parameter toolRegistry: Реестр инструментов для проверки riskClass.
    /// - Returns: Упорядоченный массив групп (каждая группа — параллельные вызовы).
    public func order(_ calls: [ToolCallRequest]) -> [[ToolCallRequest]] {
        guard !calls.isEmpty else { return [] }

        if calls.count == 1 {
            return [calls]
        }

        // Группируем по risk class priority
        var groups: [[ToolCallRequest]] = []

        // Приоритеты (Blueprint §4):
        // 1. readPublic    (priority 0) — поиск, каталоги
        // 2. readPrivate   (priority 1) — скан комнаты, фото
        // 3. internalState (priority 2) — todo, план
        // 4. draft         (priority 3) — рекомендации, планы
        // 5. meta          (priority 4) — approval requests, skills
        // 6. action        (priority 5) — экспорт, публикация
        // 7. financial     (priority 6) — покупки (MVP: заблокированы)

        let priorityMap: [String: Int] = [
            "read_public": 0,
            "read_private": 1,
            "internal_state": 2,
            "draft": 3,
            "meta": 4,
            "action": 5,
            "financial": 6
        ]

        // Группируем по приоритетам
        let groupedByPriority = Dictionary(grouping: calls) { call in
            priorityMap.first { call.name.contains($0.key) }?.value ?? 3 // default: draft
        }

        // Сортируем группы по приоритету
        let sortedPriorities = groupedByPriority.keys.sorted()

        for priority in sortedPriorities {
            guard let group = groupedByPriority[priority] else { continue }

            // Внутри одной группы: проверяем зависимости
            let subgroups = resolveDependencies(in: group)
            groups.append(contentsOf: subgroups)
        }

        logger.debug("📋 Scheduler: \(calls.count) calls → \(groups.count) групп")
        return groups
    }

    // MARK: - Private: Dependency Resolution

    /// Разделяет группу на подгруппы с учётом зависимостей.
    ///
    /// Эвристика: если tool call A содержит в аргументах результат tool call B,
    /// то B должен выполниться раньше A.
    private func resolveDependencies(in group: [ToolCallRequest]) -> [[ToolCallRequest]] {
        guard group.count > 1 else { return [group] }

        // Анализируем имена: если один call содержит имя другого в аргументах — зависимость.
        var remaining = group
        var result: [[ToolCallRequest]] = []
        var processedNames = Set<String>()

        while !remaining.isEmpty {
            let (ready, waiting) = partition(remaining, dependenciesMet: processedNames)

            if ready.isEmpty {
                // Циклическая зависимость или все waiting — выполняем всех parallel
                logger.warning("⚠️ Возможна циклическая зависимость: выполняем группу параллельно")
                result.append(remaining)
                break
            }

            result.append(ready)
            processedNames.formUnion(ready.map(\.name))
            remaining = waiting
        }

        return result
    }

    /// Разделяет calls на готовые к выполнению и ожидающие.
    private func partition(
        _ calls: [ToolCallRequest],
        dependenciesMet: Set<String>
    ) -> (ready: [ToolCallRequest], waiting: [ToolCallRequest]) {
        var ready: [ToolCallRequest] = []
        var waiting: [ToolCallRequest] = []

        for call in calls {
            // Проверяем, содержит ли аргументы ссылки на ещё не выполненные инструменты
            let hasUnmetDependencies = calls.contains { other in
                guard other.id != call.id else { return false }
                guard !dependenciesMet.contains(other.name) else { return false }
                // Проверяем, ссылаются ли аргументы call на other.name
                return referencesTool(arguments: call.arguments, toolName: other.name)
            }

            if hasUnmetDependencies {
                waiting.append(call)
            } else {
                ready.append(call)
            }
        }

        return (ready, waiting)
    }

    /// Проверяет, ссылаются ли аргументы на указанный инструмент.
    private func referencesTool(arguments: [String: Any], toolName: String) -> Bool {
        for (_, value) in arguments {
            if let str = value as? String, str.contains(toolName) {
                return true
            }
        }
        return false
    }
}
