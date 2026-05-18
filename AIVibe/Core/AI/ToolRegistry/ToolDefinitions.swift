// AIVibe/Core/AI/ToolRegistry/ToolDefinitions.swift
// Этап 1: Базовые типы Tool Registry.
// RiskClass, Permission, ToolError, Tool, ToolResult, ToolCallRequest.

import Foundation

// MARK: - Risk Class

/// Уровень риска инструмента. Определяет политику выполнения.
public enum ToolRiskClass: String, Sendable, Codable, Equatable {
    /// Безопасные операции: чтение публичных данных, поиск по базе знаний.
    case readPublic = "read_public"

    /// Чтение приватных данных пользователя (скан комнаты, фото).
    case readPrivate = "read_private"

    /// Черновики — создание рекомендаций, планов, списков без внешних действий.
    case draft = "draft"

    /// Действия с внешними эффектами: экспорт, публикация, отправка.
    case action = "action"

    /// Финансовые операции: покупка, оплата. Запрещены в MVP v1.
    case financial = "financial"

    /// Внутреннее состояние агента: todo, план.
    case internalState = "internal_state"

    /// Мета-инструменты: запрос одобрения, вызов скилла.
    case meta = "meta"
}

// MARK: - Permission Decision

/// Решение permission-системы по конкретному вызову инструмента.
public enum PermissionDecision: Sendable, Equatable {
    /// Разрешено — выполнить немедленно.
    case allow

    /// Запрещено — вернуть ошибку пользователю.
    case deny(reason: String)

    /// Требуется одобрение пользователя — приостановить выполнение.
    case approvalRequired(action: String, riskClass: ToolRiskClass)

    /// Выполнить в изолированной песочнице (read-only копия данных).
    case sandbox
}

// MARK: - Tool Error

/// Ошибки, специфичные для Tool Registry.
public enum ToolError: LocalizedError, Sendable, Equatable {
    case toolNotFound(name: String)
    case validationFailed(tool: String, reason: String)
    case permissionDenied(tool: String, reason: String)
    case executionFailed(tool: String, error: String)
    case timeout(tool: String, limit: TimeInterval)
    case resultTooLarge(tool: String, size: Int, maxAllowed: Int)
    case approvalRequired(tool: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Инструмент '\(name)' не найден"
        case .validationFailed(let tool, let reason):
            return "Ошибка валидации \(tool): \(reason)"
        case .permissionDenied(let tool, let reason):
            return "Доступ к \(tool) запрещён: \(reason)"
        case .executionFailed(let tool, let error):
            return "Ошибка выполнения \(tool): \(error)"
        case .timeout(let tool, let limit):
            return "Таймаут \(tool) (лимит \(Int(limit))с)"
        case .resultTooLarge(let tool, let size, let maxAllowed):
            return "Результат \(tool) слишком большой: \(size) > \(maxAllowed)"
        case .approvalRequired(let tool):
            return "Для \(tool) требуется подтверждение пользователя"
        }
    }
}

// MARK: - Tool Result

/// Унифицированный результат выполнения инструмента.
public struct ToolResult: Sendable, Equatable {
    /// Идентификатор вызова (привязка к toolCallId из модели).
    public let callId: UUID

    /// Имя инструмента.
    public let toolName: String

    /// Статус выполнения.
    public let status: Status

    /// Данные результата (JSON-строка или структурированный текст).
    public let data: String

    /// Время выполнения в миллисекундах.
    public let durationMs: Double

    /// Размер результата в символах.
    public let resultSize: Int

    public enum Status: String, Sendable, Equatable {
        case success
        case error
        case denied
        case approvalRequired = "approval_required"
        case timeout
        case truncated
    }

    public init(
        callId: UUID,
        toolName: String,
        status: Status,
        data: String,
        durationMs: Double,
        resultSize: Int? = nil
    ) {
        self.callId = callId
        self.toolName = toolName
        self.status = status
        self.data = data
        self.durationMs = durationMs
        self.resultSize = resultSize ?? data.count
    }

    /// Фабрика для успешного результата.
    public static func success(
        callId: UUID,
        toolName: String,
        data: String,
        durationMs: Double
    ) -> ToolResult {
        ToolResult(
            callId: callId,
            toolName: toolName,
            status: .success,
            data: data,
            durationMs: durationMs
        )
    }

    /// Фабрика для ошибки.
    public static func failure(
        callId: UUID,
        toolName: String,
        error: String,
        durationMs: Double = 0
    ) -> ToolResult {
        ToolResult(
            callId: callId,
            toolName: toolName,
            status: .error,
            data: error,
            durationMs: durationMs
        )
    }
}

// MARK: - Tool Protocol

/// Протокол инструмента агента.
/// Все инструменты — Sendable, выполняются асинхронно.
public protocol AgentTool: Sendable, Identifiable {
    /// Уникальное имя (совпадает с именем в model output tool_calls).
    var name: String { get }

    /// Человекочитаемое описание для промпта модели.
    var description: String { get }

    /// JSON Schema входных параметров (для function calling).
    var inputSchema: ToolInputSchema { get }

    /// Класс риска.
    var riskClass: ToolRiskClass { get }

    /// Таймаут выполнения (секунды).
    var timeout: TimeInterval { get }

    /// Максимальный размер результата в символах.
    var maxResultChars: Int { get }

    /// Побочные эффекты (для логирования).
    var sideEffects: ToolSideEffect { get }

    /// Валидация входных аргументов. Бросает ToolError.validationFailed при ошибке.
    func validate(_ arguments: [String: Any]) throws -> [String: Any]

    /// Выполнение инструмента.
    func execute(validated: [String: Any]) async throws -> String
}

// MARK: - Tool Input Schema

/// JSON Schema для входных параметров инструмента.
public struct ToolInputSchema: Sendable, Equatable {
    public let type: String
    public let properties: [String: SchemaProperty]
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: SchemaProperty],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Описание одного поля в JSON Schema.
public struct SchemaProperty: Sendable, Equatable {
    public let type: SchemaType
    public let description: String
    public let enumValues: [String]?

    public init(
        type: SchemaType,
        description: String,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

public enum SchemaType: String, Sendable, Equatable {
    case string
    case integer
    case number
    case boolean
    case object
    case array
}

// MARK: - Side Effects

public enum ToolSideEffect: String, Sendable, Equatable {
    /// Нет побочных эффектов (чистое чтение).
    case none

    /// Читает данные пользователя.
    case readsUserData = "reads_user_data"

    /// Создаёт/изменяет данные внутри сессии.
    case mutatesSession = "mutates_session"

    /// Делает внешний HTTP-запрос.
    case externalRequest = "external_request"

    /// Изменяет состояние вне сессии (публикация, заказ).
    case externalMutation = "external_mutation"
}

// MARK: - Tool Call Request

/// Запрос на вызов инструмента (парсится из model output).
public struct ToolCallRequest: Sendable, Equatable {
    /// ID вызова (из модели).
    public let id: UUID

    /// Имя инструмента.
    public let name: String

    /// Аргументы (JSON-словарь).
    public let arguments: [String: Any]

    public init(id: UUID, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    // MARK: - Equatable

    public static func == (lhs: ToolCallRequest, rhs: ToolCallRequest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Default AgentTool Implementation

public extension AgentTool {
    var id: String { name }

    var timeout: TimeInterval { 15.0 }
    var maxResultChars: Int { 8000 }
    var sideEffects: ToolSideEffect { .none }

    func validate(_ arguments: [String: Any]) throws -> [String: Any] {
        // Валидация по JSON Schema
        for requiredKey in inputSchema.required {
            guard arguments[requiredKey] != nil else {
                throw ToolError.validationFailed(
                    tool: name,
                    reason: "Отсутствует обязательное поле '\(requiredKey)'"
                )
            }
        }
        return arguments
    }
}
