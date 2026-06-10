// AIVibe/Core/Subscription/SubscriptionModels.swift
// Модель тарифа FREE/PRO/BUSINESS и статус подписки пользователя.
// Источник истины по статусу — backend (functions/payments, YDB);
// цены здесь только для отображения (канон — STRATEGY.md §1.3 / BUSINESS_MODEL.md §4).
// См. docs/UPGRADE_PLAN.md — Фаза 1, A3.2.

import Foundation

// MARK: - Тариф

public enum SubscriptionTier: String, Codable, Sendable, Equatable, CaseIterable {
    case free
    case pro
    case business

    /// Название для UI.
    public var displayName: String {
        switch self {
        case .free: return "FREE"
        case .pro: return "PRO"
        case .business: return "BUSINESS"
        }
    }

    /// Цена в месяц (₽) — только для отображения; списание делает backend/ЮKassa.
    public var monthlyPriceRub: Int {
        switch self {
        case .free: return 0
        case .pro: return 599
        case .business: return 2490
        }
    }
}

// MARK: - Статус подписки

public struct SubscriptionStatus: Codable, Sendable, Equatable {
    /// Тариф, который оплачен (или .free).
    public let tier: SubscriptionTier
    /// Активна ли подписка прямо сейчас (по данным backend).
    public let isActive: Bool
    /// Когда истекает (nil для free/неактивной).
    public let expiresAt: Date?

    public init(tier: SubscriptionTier, isActive: Bool, expiresAt: Date?) {
        self.tier = tier
        self.isActive = isActive
        self.expiresAt = expiresAt
    }

    /// Бесплатный статус по умолчанию (нет сети / нет записи).
    public static let free = SubscriptionStatus(tier: .free, isActive: false, expiresAt: nil)

    /// Эффективный тариф для гейтинга фич: неактивная подписка = FREE.
    public var effectiveTier: SubscriptionTier {
        isActive ? tier : .free
    }

    /// Маппинг ответа backend (functions/payments, action: status).
    /// Неизвестный план или неактивность безопасно сводятся к free-поведению.
    public static func fromBackend(plan: String, isActive: Bool, expiresAt: String?) -> SubscriptionStatus {
        let tier = SubscriptionTier(rawValue: plan) ?? .free
        return SubscriptionStatus(
            tier: tier,
            isActive: isActive && tier != .free,
            expiresAt: expiresAt.flatMap(parseISO8601)
        )
    }
}

// MARK: - Парсинг дат

/// ISO8601 с миллисекундами (JS `toISOString()` → "2026-07-09T18:00:00.000Z") и без них.
func parseISO8601(_ string: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: string) { return date }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}
