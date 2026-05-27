// AIVibe/Core/AI/ToolRegistry/ToolRegistry.swift
// Этап 5: Центральный реестр инструментов агента.
// Actor: регистрация, поиск, валидация, выполнение с permission check и лимитами.
// Blueprint §6: Tool Registry — единая точка входа для всех инструментов.

import Foundation
import Logging

// MARK: - Tool Registry

/// Центральный actor-реестр всех инструментов агента.
///
/// Обязанности:
/// 1. Регистрация/удаление инструментов
/// 2. Поиск инструмента по имени
/// 3. Валидация аргументов
/// 4. Permission check (через PermissionEngine)
/// 5. Выполнение с таймаутом
/// 6. Ограничение размера результата (через ResultLimiter)
/// 7. Логирование каждого вызова
///
/// Blueprint §6: Tool Registry — general-purpose + domain-specific tools.
public actor ToolRegistry {

    // MARK: - Properties

    /// Зарегистрированные инструменты (ключ = имя).
    private var tools: [String: any AgentTool] = [:]

    /// Permission engine.
    private let permissionEngine: PermissionEngine

    /// Ограничитель размера результатов.
    private let resultLimiter: ResultLimiter

    /// Логгер.
    private let logger = Logger(label: "ai.tool-registry")

    // MARK: - Init

    public init(
        permissionEngine: PermissionEngine = PermissionEngine(),
        resultLimiter: ResultLimiter = ResultLimiter()
    ) {
        self.permissionEngine = permissionEngine
        self.resultLimiter = resultLimiter
    }

    // MARK: - Registration

    /// Регистрирует один инструмент.
    /// - Если инструмент с таким именем уже существует — заменяется.
    public func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
        logger.info("✅ Инструмент зарегистрирован: \(tool.name) [\(tool.riskClass.rawValue)]")
    }

    /// Регистрирует несколько инструментов.
    public func register(_ newTools: [any AgentTool]) {
        for tool in newTools {
            register(tool)
        }
    }

    /// Регистрирует все domain-specific инструменты (Blueprint §6).
    /// - analyze_room_scan
    /// - search_marketplace_furniture
    /// - recommend_style
    /// - generate_arrangement_plan
    /// - draft_shopping_list
    public func registerDomainTools() {
        register(AnalyzeRoomScanTool())
        register(SearchMarketplaceFurnitureTool())
        register(RecommendStyleTool())
        register(GenerateArrangementTool())
        register(DraftShoppingListTool())
        logger.info("🏗️ Domain-инструменты зарегистрированы: 5/5 (analyze_room_scan, search_marketplace_furniture, recommend_style, generate_arrangement_plan, draft_shopping_list)")
    }

    /// Удаляет инструмент по имени.
    public func unregister(named name: String) {
        tools.removeValue(forKey: name)
        logger.info("🗑️ Инструмент удалён: \(name)")
    }

    /// Возвращает имена всех зарегистрированных инструментов.
    public var registeredToolNames: [String] {
        Array(tools.keys).sorted()
    }

    // MARK: - Query

    /// Находит инструмент по имени.
    /// - Returns: `nil`, если инструмент не найден.
    public func get(named name: String) -> (any AgentTool)? {
        tools[name]
    }

    /// Возвращает все инструменты, видимые в текущем контексте (BluePrint §4: `visibleTools`).
    public func visibleTools() -> [any AgentTool] {
        Array(tools.values)
    }

    /// Возвращает инструменты, отфильтрованные по risk class.
    public func tools(withRiskClass riskClass: ToolRiskClass) -> [any AgentTool] {
        tools.values.filter { $0.riskClass == riskClass }
    }

    // MARK: - Execute (основной метод)

    /// Выполняет tool call: валидация → permission → выполнение → лимит.
    ///
    /// - Parameter call: Запрос на вызов инструмента (из model output).
    /// - Returns: `ToolResult` с результатом выполнения.
    // swiftlint:disable:next function_body_length
    public func execute(call: ToolCallRequest) async -> ToolResult {
        let startTime = Date()

        // 1. Поиск инструмента
        guard let tool = tools[call.name] else {
            let errorMsg = "Инструмент '\(call.name)' не найден. Доступны: \(registeredToolNames.joined(separator: ", "))"
            logger.error("❌ \(errorMsg)")
            return ToolResult.failure(
                callId: call.id,
                toolName: call.name,
                error: errorMsg,
                durationMs: 0
            )
        }

        // 2. Валидация аргументов
        let validated: [String: Any]
        do {
            validated = try tool.validate(call.arguments)
        } catch let error as ToolError {
            logger.warning("⚠️ Валидация \(call.name): \(error.localizedDescription)")
            return ToolResult.failure(
                callId: call.id,
                toolName: call.name,
                error: error.localizedDescription,
                durationMs: Date().timeIntervalSince(startTime) * 1000
            )
        } catch {
            return ToolResult.failure(
                callId: call.id,
                toolName: call.name,
                error: error.localizedDescription,
                durationMs: Date().timeIntervalSince(startTime) * 1000
            )
        }

        // 3. Permission check
        let decision = await permissionEngine.evaluate(
            toolName: call.name,
            riskClass: tool.riskClass,
            arguments: validated
        )

        switch decision {
        case .deny(let reason):
            logger.warning("🚫 Доступ запрещён: \(call.name) — \(reason)")
            return ToolResult(
                callId: call.id,
                toolName: call.name,
                status: .denied,
                data: reason,
                durationMs: Date().timeIntervalSince(startTime) * 1000
            )

        case .approvalRequired(let action, let riskClass):
            logger.info("🔐 Требуется одобрение: \(action) [\(riskClass.rawValue)]")
            return ToolResult(
                callId: call.id,
                toolName: call.name,
                status: .approvalRequired,
                data: "Требуется подтверждение действия '\(action)'",
                durationMs: Date().timeIntervalSince(startTime) * 1000
            )

        case .sandbox:
            // MVP: sandbox = read-only копия, пока выполняем как обычно
            logger.debug("🏖️ Sandbox: \(call.name)")
            // fallthrough к allow

        case .allow:
            break
        }

        // 4. Выполнение с таймаутом
        let result: String
        do {
            result = try await executeWithTimeout(tool: tool, validated: validated)
        } catch let error as ToolError {
            logger.error("❌ Ошибка выполнения \(call.name): \(error.localizedDescription)")
            return ToolResult.failure(
                callId: call.id,
                toolName: call.name,
                error: error.localizedDescription,
                durationMs: Date().timeIntervalSince(startTime) * 1000
            )
        } catch {
            return ToolResult.failure(
                callId: call.id,
                toolName: call.name,
                error: error.localizedDescription,
                durationMs: Date().timeIntervalSince(startTime) * 1000
            )
        }

        // 5. Лимит размера
        let durationMs = Date().timeIntervalSince(startTime) * 1000
        let rawResult = ToolResult.success(
            callId: call.id,
            toolName: call.name,
            data: result,
            durationMs: durationMs
        )

        let finalResult = resultLimiter.enforce(rawResult)

        logger.info("✅ \(call.name): \(finalResult.status.rawValue), \(Int(durationMs))мс, \(finalResult.resultSize) символов")

        return finalResult
    }

    // MARK: - Private: Timeout

    /// Выполняет инструмент с таймаутом.
    private func executeWithTimeout(
        tool: any AgentTool,
        validated: [String: Any]
    ) async throws -> String {
        let timeout = tool.timeout

        let box = SendableBox(validated)
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Задача выполнения
            group.addTask {
                try await tool.execute(validated: box.value)
            }

            // Задача таймаута
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ToolError.timeout(tool: tool.name, limit: timeout)
            }

            // Ждём первый результат (или таймаут)
            let firstResult = try await group.next()!
            group.cancelAll()
            return firstResult
        }
    }

    // MARK: - Permission Management

    /// Обновляет контекст сессии в PermissionEngine.
    public func updateSessionContext(_ context: SessionContext) async {
        await permissionEngine.updateContext(context)
    }
}

// MARK: - TCA Dependency

#if canImport(ComposableArchitecture)
import ComposableArchitecture

extension DependencyValues {
    public var toolRegistry: ToolRegistry {
        get { self[ToolRegistryKey.self] }
        set { self[ToolRegistryKey.self] = newValue }
    }
}

private enum ToolRegistryKey: DependencyKey {
    static let liveValue = ToolRegistry()
    static let testValue = ToolRegistry()
    static let previewValue: ToolRegistry = {
        let registry = ToolRegistry()
        // Preview: регистрируем domain-specific инструменты (Blueprint §6)
        Task {
            await registry.registerDomainTools()
        }
        return registry
    }()
}

// MARK: - AgentLoop Dependency (Stage 3)

extension DependencyValues {
    public var agentLoop: AgentLoop {
        get { self[AgentLoopKey.self] }
        set { self[AgentLoopKey.self] = newValue }
    }
}

private enum AgentLoopKey: DependencyKey {
    static let liveValue: AgentLoop = {
        let registry = ToolRegistry()
        Task {
            await registry.registerDomainTools()
        }
        return AgentLoop(
            toolRegistry: registry,
            providerRouter: AIProviderRouter(providers: [])
        )
    }()

    static let testValue: AgentLoop = {
        let registry = ToolRegistry()
        return AgentLoop(
            toolRegistry: registry,
            providerRouter: AIProviderRouter(providers: [])
        )
    }()

    static let previewValue: AgentLoop = {
        let registry = ToolRegistry()
        Task {
            await registry.registerDomainTools()
        }
        return AgentLoop(
            toolRegistry: registry,
            providerRouter: AIProviderRouter(providers: [MockAIProvider()])
        )
    }()
}
#endif
