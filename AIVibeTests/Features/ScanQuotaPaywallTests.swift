// AIVibeTests/Features/ScanQuotaPaywallTests.swift
// A3.3 (Фаза 1, UPGRADE_PLAN): квота сканов FREE (3/мес) и пейволл-фича.

import ComposableArchitecture
import XCTest
@testable import AIVibe

@MainActor
final class ScanQuotaPaywallTests: XCTestCase {

    // MARK: - ScanQuota (чистая логика)

    func testFreeTierAllowsThreeScansPerMonth() {
        var quota = ScanQuota(monthKey: "2026-06", used: 0)
        XCTAssertTrue(quota.canStartScan(tier: .free))   // 1-й
        quota = quota.afterScan()
        XCTAssertTrue(quota.canStartScan(tier: .free))   // 2-й
        quota = quota.afterScan()
        XCTAssertTrue(quota.canStartScan(tier: .free))   // 3-й
        quota = quota.afterScan()
        XCTAssertFalse(quota.canStartScan(tier: .free))  // 4-й — блок
        XCTAssertEqual(quota.freeRemaining, 0)
    }

    func testProAndBusinessUnlimited() {
        let exhausted = ScanQuota(monthKey: "2026-06", used: 99)
        XCTAssertTrue(exhausted.canStartScan(tier: .pro))
        XCTAssertTrue(exhausted.canStartScan(tier: .business))
    }

    func testQuotaResetsOnNewMonth() throws {
        let storage = InMemoryStorageClient()
        ScanQuota(monthKey: "2026-05", used: 3).save(to: storage)

        let june = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 6, day: 10).date
        )
        let quota = ScanQuota.load(from: storage, now: june)

        XCTAssertEqual(quota.monthKey, "2026-06")
        XCTAssertEqual(quota.used, 0)                    // новый месяц — счётчик обнулён
        XCTAssertTrue(quota.canStartScan(tier: .free))
    }

    func testQuotaPersistsWithinSameMonth() throws {
        let storage = InMemoryStorageClient()
        let june = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 6, day: 10).date
        )

        ScanQuota(monthKey: ScanQuota.currentMonthKey(now: june), used: 2).save(to: storage)
        let quota = ScanQuota.load(from: storage, now: june)

        XCTAssertEqual(quota.used, 2)
        XCTAssertEqual(quota.freeRemaining, 1)
    }

    func testCurrentMonthKeyFormat() throws {
        let date = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 6, day: 1).date
        )
        XCTAssertEqual(ScanQuota.currentMonthKey(now: date), "2026-06")
    }

    // MARK: - PaywallFeature

    func testOnAppearLoadsStatus() async {
        let pro = SubscriptionStatus(tier: .pro, isActive: true, expiresAt: nil)
        let store = TestStore(initialState: PaywallFeature.State()) {
            PaywallFeature()
        } withDependencies: {
            $0.subscriptionClient = SubscriptionClient(
                fetchStatus: { pro },
                createPayment: { _ in throw SubscriptionError.notConfigured }
            )
        }

        await store.send(.onAppear)
        await store.receive(\.statusLoaded) {
            $0.status = pro
        }
    }

    func testRefreshStatusShowsSpinnerThenResult() async {
        let store = TestStore(initialState: PaywallFeature.State()) {
            PaywallFeature()
        } withDependencies: {
            $0.subscriptionClient = SubscriptionClient(
                fetchStatus: { .free },
                createPayment: { _ in throw SubscriptionError.notConfigured }
            )
        }

        await store.send(.refreshStatusTapped) {
            $0.isRefreshing = true
        }
        await store.receive(\.statusLoaded) {
            $0.isRefreshing = false
        }
    }

    func testTierSelection() async {
        let store = TestStore(initialState: PaywallFeature.State()) {
            PaywallFeature()
        }
        await store.send(.tierSelected(.business)) {
            $0.selectedTier = .business
        }
    }

    // MARK: - Гейт сканов в RoomScanFlowFeature

    private func makeScanStore(
        storage: InMemoryStorageClient,
        status: SubscriptionStatus
    ) -> TestStore<RoomScanFlowFeature.State, RoomScanFlowFeature.Action> {
        TestStore(initialState: RoomScanFlowFeature.State()) {
            RoomScanFlowFeature()
        } withDependencies: {
            $0.storageClient = storage
            $0.subscriptionClient = SubscriptionClient(
                fetchStatus: { status },
                createPayment: { _ in throw SubscriptionError.notConfigured }
            )
        }
    }

    func testScanGateBlocksFreeUserAtLimit() async {
        let storage = InMemoryStorageClient()
        ScanQuota(monthKey: ScanQuota.currentMonthKey(), used: 3).save(to: storage)

        let store = makeScanStore(storage: storage, status: .free)
        await store.send(.startScanTapped) {
            $0.paywallTrigger = .scanLimit   // фаза остаётся .intro
        }
        await store.send(.paywallDismissed) {
            $0.paywallTrigger = nil
        }
    }

    func testScanGateAllowsProAtExhaustedQuota() async {
        let storage = InMemoryStorageClient()
        ScanQuota(monthKey: ScanQuota.currentMonthKey(), used: 99).save(to: storage)

        let pro = SubscriptionStatus(tier: .pro, isActive: true, expiresAt: nil)
        let store = makeScanStore(storage: storage, status: pro)

        // Статус подписки в state — как после flowAppeared.
        await store.send(.subscriptionStatusLoaded(pro)) {
            $0.subscriptionStatus = pro
        }
        await store.send(.startScanTapped) {
            $0.phase = .scanning             // PRO — безлимит
        }
    }

    func testScanGateConsumesQuotaOnStart() async throws {
        let storage = InMemoryStorageClient()
        let store = makeScanStore(storage: storage, status: .free)

        await store.send(.startScanTapped) {
            $0.phase = .scanning
        }

        let saved: ScanQuota = try XCTUnwrap(try storage.load(forKey: ScanQuota.storageKey))
        XCTAssertEqual(saved.used, 1)        // квота списана на старте
    }

    func testFlowAppearedLoadsSubscriptionStatus() async {
        let pro = SubscriptionStatus(tier: .pro, isActive: true, expiresAt: nil)
        let store = makeScanStore(storage: InMemoryStorageClient(), status: pro)

        await store.send(.flowAppeared)
        await store.receive(\.subscriptionStatusLoaded) {
            $0.subscriptionStatus = pro
        }
    }

    // MARK: - Гейт ручного ввода (путь без LiDAR, A1 — тоже «скан»)

    func testManualEntryGateBlocksFreeUserAtLimit() async {
        let storage = InMemoryStorageClient()
        ScanQuota(monthKey: ScanQuota.currentMonthKey(), used: 3).save(to: storage)

        let store = makeScanStore(storage: storage, status: .free)
        await store.send(.manualEntryTapped) {
            $0.paywallTrigger = .scanLimit   // фаза остаётся .intro — форма не открывается
        }
    }

    func testManualDimensionsSubmitConsumesQuota() async throws {
        let storage = InMemoryStorageClient()
        let store = makeScanStore(storage: storage, status: .free)
        let expected = try RoomGeometry.manualRectangular(widthM: 4, depthM: 5, heightM: 2.7)

        await store.send(.manualEntryTapped) {
            $0.phase = .manualEntry
        }
        await store.send(.manualDimensionsSubmitted(widthM: 4, depthM: 5, heightM: 2.7)) {
            $0.phase = .styleSelection
        }
        await store.receive(\.geometryExtracted) {
            $0.geometry = expected
            $0.metrics = RoomMetrics(area: "20 м²", height: "2.7 м", objectsCount: 0)
        }

        let saved: ScanQuota = try XCTUnwrap(try storage.load(forKey: ScanQuota.storageKey))
        XCTAssertEqual(saved.used, 1)        // списание — при успешном вводе размеров
    }

    func testManualEntryGateAllowsProAtExhaustedQuota() async {
        let storage = InMemoryStorageClient()
        ScanQuota(monthKey: ScanQuota.currentMonthKey(), used: 99).save(to: storage)
        let pro = SubscriptionStatus(tier: .pro, isActive: true, expiresAt: nil)

        let store = makeScanStore(storage: storage, status: pro)
        await store.send(.subscriptionStatusLoaded(pro)) {
            $0.subscriptionStatus = pro
        }
        await store.send(.manualEntryTapped) {
            $0.phase = .manualEntry          // PRO — безлимит
        }
    }

    func testInvalidManualDimensionsDoNotConsumeQuota() async {
        let storage = InMemoryStorageClient()
        let store = makeScanStore(storage: storage, status: .free)

        await store.send(.manualEntryTapped) {
            $0.phase = .manualEntry
        }
        await store.send(.manualDimensionsSubmitted(widthM: 1, depthM: 1, heightM: 2.7)) {
            $0.manualEntryError = RoomGeometryError.roomTooSmall(area: 1).localizedDescription
        }

        // Ошибка валидации — квота не тронута.
        let saved: ScanQuota? = (try? storage.load(forKey: ScanQuota.storageKey)) ?? nil
        XCTAssertNil(saved)
    }
}
