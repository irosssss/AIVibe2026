// AIVibeTests/Features/SubscriptionModelsTests.swift
// A3.2 (Фаза 1, UPGRADE_PLAN): модель тарифа и маппинг ответа backend.

import XCTest
@testable import AIVibe

final class SubscriptionModelsTests: XCTestCase {

    // MARK: - Канон цен (STRATEGY §1.3 / BUSINESS_MODEL §4)

    func testTierPricesMatchCanon() {
        XCTAssertEqual(SubscriptionTier.free.monthlyPriceRub, 0)
        XCTAssertEqual(SubscriptionTier.pro.monthlyPriceRub, 599)
        XCTAssertEqual(SubscriptionTier.business.monthlyPriceRub, 2490)
    }

    // MARK: - Маппинг ответа backend

    func testFromBackendActivePro() {
        let status = SubscriptionStatus.fromBackend(
            plan: "pro",
            isActive: true,
            expiresAt: "2026-07-09T18:00:00.000Z"   // JS toISOString — с миллисекундами
        )
        XCTAssertEqual(status.tier, .pro)
        XCTAssertTrue(status.isActive)
        XCTAssertNotNil(status.expiresAt)
        XCTAssertEqual(status.effectiveTier, .pro)
    }

    func testFromBackendUnknownPlanFallsBackToFree() {
        let status = SubscriptionStatus.fromBackend(plan: "platinum", isActive: true, expiresAt: nil)
        XCTAssertEqual(status.tier, .free)
        XCTAssertFalse(status.isActive)              // free не бывает «активным»
        XCTAssertEqual(status.effectiveTier, .free)
    }

    func testFromBackendInactiveProGatesAsFree() {
        let status = SubscriptionStatus.fromBackend(plan: "pro", isActive: false, expiresAt: nil)
        XCTAssertEqual(status.tier, .pro)
        XCTAssertFalse(status.isActive)
        XCTAssertEqual(status.effectiveTier, .free)  // главный инвариант гейтинга
    }

    func testFromBackendFreePlan() {
        let status = SubscriptionStatus.fromBackend(plan: "free", isActive: false, expiresAt: nil)
        XCTAssertEqual(status, .free)
    }

    // MARK: - Парсинг ISO8601

    func testParseISO8601WithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(parseISO8601("2026-07-09T18:00:00.000Z"))  // JS toISOString
        XCTAssertNotNil(parseISO8601("2026-07-09T18:00:00Z"))      // без миллисекунд
        XCTAssertNil(parseISO8601("не дата"))
    }

    // MARK: - Codable round-trip (кеш в StorageClient)

    func testStatusCodableRoundTrip() throws {
        let original = SubscriptionStatus(
            tier: .pro,
            isActive: true,
            expiresAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubscriptionStatus.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
