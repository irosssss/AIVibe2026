// AIVibe/Core/Subscription/ScanQuota.swift
// Месячная квота сканирований для FREE-тарифа (3 скана/мес — канон STRATEGY.md §1.3).
// Чистая, тестируемая логика; персист — через StorageClient (key scan_quota_v1).
// PRO/BUSINESS — безлимит. См. docs/UPGRADE_PLAN.md — Фаза 1, A3.3.

import Foundation

public struct ScanQuota: Codable, Sendable, Equatable {
    /// Месяц, к которому относится счётчик, в формате "2026-06".
    public let monthKey: String
    /// Сколько сканов уже использовано в этом месяце.
    public let used: Int

    public init(monthKey: String, used: Int) {
        self.monthKey = monthKey
        self.used = used
    }

    /// Лимит сканов в месяц на FREE (канон STRATEGY §1.3: «3 скана/мес»).
    public static let freeMonthlyLimit = 3

    /// Ключ хранения в StorageClient.
    public static let storageKey = "scan_quota_v1"

    /// Ключ текущего месяца ("2026-06").
    public static func currentMonthKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Загружает квоту из хранилища; при смене месяца счётчик обнуляется.
    public static func load(
        from storage: any StorageClientProtocol,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ScanQuota {
        let key = currentMonthKey(now: now, calendar: calendar)
        if let saved: ScanQuota = (try? storage.load(forKey: storageKey)) ?? nil,
           saved.monthKey == key {
            return saved
        }
        return ScanQuota(monthKey: key, used: 0)
    }

    /// Можно ли начать ещё один скан на данном тарифе.
    /// FREE — до freeMonthlyLimit; PRO/BUSINESS — безлимит.
    public func canStartScan(tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free: return used < Self.freeMonthlyLimit
        case .pro, .business: return true
        }
    }

    /// Сколько сканов осталось на FREE (для UI «осталось 2 из 3»).
    public var freeRemaining: Int {
        max(0, Self.freeMonthlyLimit - used)
    }

    /// Квота после ещё одного скана.
    public func afterScan() -> ScanQuota {
        ScanQuota(monthKey: monthKey, used: used + 1)
    }

    /// Записывает квоту в хранилище (ошибки записи не фатальны для UX).
    public func save(to storage: any StorageClientProtocol) {
        try? storage.save(self, forKey: Self.storageKey)
    }
}
