// AIVibe/Core/AI/ToolRegistry/PermissionEngine.swift
// Этап 2: Permission Matrix Evaluator.
// Оценивает каждый tool call: allow / deny / approvalRequired / sandbox.
// Основан на MVP Agent Blueprint — раздел 12 "Safety and approval policy".

import Foundation

// MARK: - Permission Engine

/// Permission Engine оценивает каждый вызов инструмента против матрицы разрешений.
///
/// Правила (из Blueprint §12):
/// - readPublic / readPrivate → allow в рамках сессии
/// - draft → allow (рекомендации, планы, списки)
/// - action → approval-gated (экспорт, публикация)
/// - financial → DENY в MVP v1
/// - internalState / meta → allow
///
/// Приоритет: deny > approval-gated > allow
public actor PermissionEngine {

    // MARK: - Custom Rules

    /// Кастомные правила разрешений (проверяются до матрицы по умолчанию).
    private var customRules: [String: CustomPermissionRule] = [:]

    /// Контекст сессии (ID пользователя, статус подписки, роль).
    private var sessionContext: SessionContext

    // MARK: - Init

    public init(
        sessionContext: SessionContext = .default,
        customRules: [String: CustomPermissionRule] = [:]
    ) {
        self.sessionContext = sessionContext
        self.customRules = customRules
    }

    // MARK: - Public API

    /// Оценивает, разрешён ли вызов инструмента.
    ///
    /// Порядок проверки:
    /// 1. Кастомное правило (если задано)
    /// 2. Стандартная матрица по riskClass
    /// 3. Контекст сессии (например, пользователь заблокирован)
    ///
    /// - Returns: `PermissionDecision` — allow, deny, approvalRequired, sandbox.
    public func evaluate(
        toolName: String,
        riskClass: ToolRiskClass,
        arguments: [String: Any]
    ) -> PermissionDecision {

        // 0. Проверка блокировки пользователя
        if sessionContext.isBlocked {
            return .deny(reason: "Пользователь заблокирован")
        }

        // 1. Кастомное правило
        if let rule = customRules[toolName] {
            return rule.evaluate(toolName: toolName, riskClass: riskClass, arguments: arguments, context: sessionContext)
        }

        // 2. Стандартная матрица
        return evaluateByRiskClass(toolName: toolName, riskClass: riskClass)
    }

    /// Обновляет контекст сессии (например, после авторизации).
    public func updateContext(_ context: SessionContext) {
        self.sessionContext = context
    }

    /// Регистрирует кастомное правило для инструмента.
    public func registerRule(for toolName: String, rule: CustomPermissionRule) {
        customRules[toolName] = rule
    }

    // MARK: - Private: Matrix

    private func evaluateByRiskClass(toolName: String, riskClass: ToolRiskClass) -> PermissionDecision {
        switch riskClass {

        case .readPublic, .readPrivate:
            // Чтение данных разрешено в рамках сессии
            return .allow

        case .draft:
            // Черновики всегда разрешены
            return .allow

        case .action:
            // Действия с внешними эффектами требуют одобрения
            return .approvalRequired(
                action: toolName,
                riskClass: riskClass
            )

        case .financial:
            // Финансовые операции ЗАПРЕЩЕНЫ в MVP v1
            return .deny(reason: "Финансовые операции отключены в MVP v1. Покупки через маркетплейс будут доступны в следующей версии.")

        case .internalState:
            // Внутреннее состояние — всегда разрешено
            return .allow

        case .meta:
            // Мета-инструменты — разрешены
            return .allow
        }
    }
}

// MARK: - Session Context

/// Контекст пользовательской сессии для permission checks.
public struct SessionContext: Sendable, Equatable {
    /// ID пользователя.
    public let userId: String

    /// Роль пользователя.
    public let role: UserRole

    /// Заблокирован ли пользователь.
    public let isBlocked: Bool

    /// Активна ли платная подписка.
    public let hasSubscription: Bool

    /// Максимальный бюджет (если есть ограничение).
    public let budgetLimitRub: Int?

    public init(
        userId: String = "anonymous",
        role: UserRole = .user,
        isBlocked: Bool = false,
        hasSubscription: Bool = false,
        budgetLimitRub: Int? = nil
    ) {
        self.userId = userId
        self.role = role
        self.isBlocked = isBlocked
        self.hasSubscription = hasSubscription
        self.budgetLimitRub = budgetLimitRub
    }

    public static let `default` = SessionContext()
}

public enum UserRole: String, Sendable, Equatable {
    case user
    case designer
    case admin
}

// MARK: - Custom Permission Rule

/// Кастомное правило разрешения для конкретного инструмента.
public struct CustomPermissionRule: Sendable {
    /// Функция оценки: принимает контекст и возвращает решение.
    public let evaluate: @Sendable (String, ToolRiskClass, [String: Any], SessionContext) -> PermissionDecision

    public init(
        evaluate: @escaping @Sendable (String, ToolRiskClass, [String: Any], SessionContext) -> PermissionDecision
    ) {
        self.evaluate = evaluate
    }
}

// MARK: - Predefined Rules

extension CustomPermissionRule {

    /// Всегда запрещать (например, `confirm_purchase_order` в MVP).
    public static func alwaysDeny(reason: String) -> CustomPermissionRule {
        CustomPermissionRule { _, _, _, _ in
            .deny(reason: reason)
        }
    }

    /// Требовать одобрения, если бюджет превышен.
    public static func approvalIfOverBudget(thresholdRub: Int) -> CustomPermissionRule {
        CustomPermissionRule { toolName, riskClass, arguments, context in
            // Проверяем, есть ли в аргументах поле с бюджетом
            if let totalPrice = arguments["total_price_rub"] as? Int,
               totalPrice > thresholdRub {
                return .approvalRequired(
                    action: toolName,
                    riskClass: riskClass
                )
            }
            return .allow
        }
    }

    /// Разрешать только администраторам.
    public static func adminOnly(reason: String = "Только для администраторов") -> CustomPermissionRule {
        CustomPermissionRule { _, _, _, context in
            context.role == .admin
                ? .allow
                : .deny(reason: reason)
        }
    }
}
