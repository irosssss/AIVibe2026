// AIVibeTests/Features/ManualRoomEntryTests.swift
// A1 (Фаза 1, UPGRADE_PLAN): путь без LiDAR — построитель геометрии из размеров
// и поток редьюсера intro → manualEntry → styleSelection.

import ComposableArchitecture
import XCTest
@testable import AIVibe

@MainActor
final class ManualRoomEntryTests: XCTestCase {

    // MARK: - Построитель геометрии (чистая логика)

    func testBuilderProducesRectangularGeometry() throws {
        let geo = try RoomGeometry.manualRectangular(widthM: 4, depthM: 5, heightM: 2.7)
        XCTAssertEqual(geo.area, 20, accuracy: 0.001)
        XCTAssertEqual(geo.perimeter, 18, accuracy: 0.001)            // 2*(4+5)
        XCTAssertEqual(geo.ceilingHeight, 2.7, accuracy: 0.001)
        XCTAssertEqual(geo.walls.count, 4)
        XCTAssertEqual(geo.walls.map { $0.length }, [4, 5, 4, 5])
        XCTAssertTrue(geo.doors.isEmpty)
        XCTAssertTrue(geo.windows.isEmpty)
    }

    func testBuilderThrowsForTooSmallRoom() {
        XCTAssertThrowsError(try RoomGeometry.manualRectangular(widthM: 1, depthM: 1, heightM: 2.7)) { error in
            XCTAssertEqual(error as? RoomGeometryError, .roomTooSmall(area: 1))
        }
    }

    func testIsValidManualRoomBounds() {
        XCTAssertTrue(RoomGeometry.isValidManualRoom(widthM: 4, depthM: 5, heightM: 2.7))
        XCTAssertFalse(RoomGeometry.isValidManualRoom(widthM: 1.5, depthM: 2, heightM: 2.7)) // площадь 3 < 4
        XCTAssertFalse(RoomGeometry.isValidManualRoom(widthM: 0.5, depthM: 5, heightM: 2.7)) // ширина < 1
        XCTAssertFalse(RoomGeometry.isValidManualRoom(widthM: 4, depthM: 5, heightM: 1.5))   // высота < 2
        XCTAssertFalse(RoomGeometry.isValidManualRoom(widthM: 40, depthM: 5, heightM: 2.7))  // ширина > 30
    }

    // MARK: - Поток редьюсера

    func testManualEntryTappedOpensForm() async {
        let store = TestStore(initialState: RoomScanFlowFeature.State()) {
            RoomScanFlowFeature()
        }
        await store.send(.manualEntryTapped) {
            $0.phase = .manualEntry
        }
    }

    func testManualDimensionsSubmittedBuildsGeometryAndGoesToStyle() async throws {
        let expected = try RoomGeometry.manualRectangular(widthM: 4, depthM: 5, heightM: 2.7)

        let store = TestStore(initialState: RoomScanFlowFeature.State(phase: .manualEntry)) {
            RoomScanFlowFeature()
        }

        await store.send(.manualDimensionsSubmitted(widthM: 4, depthM: 5, heightM: 2.7)) {
            $0.phase = .styleSelection
        }
        await store.receive(\.geometryExtracted) {
            $0.geometry = expected
            $0.metrics = RoomMetrics(area: "20 м²", height: "2.7 м", objectsCount: 0)
        }
    }

    func testManualDimensionsTooSmallShowsError() async {
        let store = TestStore(initialState: RoomScanFlowFeature.State(phase: .manualEntry)) {
            RoomScanFlowFeature()
        }
        await store.send(.manualDimensionsSubmitted(widthM: 1, depthM: 1, heightM: 2.7)) {
            $0.manualEntryError = RoomGeometryError.roomTooSmall(area: 1).localizedDescription
        }
        // Фаза не меняется — пользователь остаётся на форме.
    }

    func testBackFromManualEntryReturnsToIntro() async {
        let store = TestStore(initialState: RoomScanFlowFeature.State(phase: .manualEntry)) {
            RoomScanFlowFeature()
        }
        await store.send(.backFromManualEntryTapped) {
            $0.phase = .intro
        }
    }
}
