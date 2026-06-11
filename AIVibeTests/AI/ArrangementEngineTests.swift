// AIVibeTests/AI/ArrangementEngineTests.swift
// A2: тесты детерминированного движка расстановки (жадная минимизация стоимости).
// Проверяет: детерминизм, стены/границы, зоны дверей, парные правила,
// переполнение комнаты, floorBounds, чистоту по CollisionDetector.

import XCTest
import simd
@testable import AIVibe

final class ArrangementEngineTests: XCTestCase {

    private let engine = ArrangementEngine()

    // MARK: - Хелперы: комната и мебель

    /// Прямоугольная комната width×depth с дверью в ближней стене (z = depth).
    private func makeRoom(width: Float = 5.0, depth: Float = 3.0, withDoor: Bool = true) -> RoomGeometry {
        let w = Double(width)
        let d = Double(depth)
        let h = 2.7
        let walls = [
            WallGeometry(start: SIMD3<Float>(0, 0, 0), end: SIMD3<Float>(width, 0, 0), length: w, height: h, isExterior: true),
            WallGeometry(start: SIMD3<Float>(width, 0, 0), end: SIMD3<Float>(width, 0, depth), length: d, height: h, isExterior: false),
            WallGeometry(start: SIMD3<Float>(width, 0, depth), end: SIMD3<Float>(0, 0, depth), length: w, height: h, isExterior: false),
            WallGeometry(start: SIMD3<Float>(0, 0, depth), end: SIMD3<Float>(0, 0, 0), length: d, height: h, isExterior: false)
        ]
        let doors = withDoor
            ? [DoorGeometry(position: SIMD3<Float>(width - 0.6, 0, depth), width: 0.9, height: 2.1, wallIndex: 2)]
            : []
        return RoomGeometry(
            area: w * d,
            perimeter: 2 * (w + d),
            ceilingHeight: h,
            walls: walls,
            doors: doors,
            windows: [],
            outlets: [],
            normalizedOrigin: .zero
        )
    }

    private func makeItem(_ itemType: String, w: Float, h: Float, d: Float) -> FurnitureItem {
        FurnitureItem(
            itemType: itemType,
            brand: "Тест",
            article: "",
            position: .zero,
            rotation: 0,
            size: SIMD3<Float>(w, h, d),
            usdzURL: ""
        )
    }

    // MARK: - Детерминизм

    func testSameInputProducesSameArrangement() {
        let room = makeRoom()
        let items = [
            makeItem("диван", w: 2.2, h: 0.85, d: 0.95),
            makeItem("журнальный стол", w: 0.9, h: 0.45, d: 0.6),
            makeItem("шкаф", w: 1.8, h: 2.2, d: 0.6)
        ]

        let first = engine.arrange(items: items, room: room)
        let second = engine.arrange(items: items, room: room)

        XCTAssertEqual(first.placedItems.map(\.position), second.placedItems.map(\.position))
        XCTAssertEqual(first.placedItems.map(\.rotation), second.placedItems.map(\.rotation))
    }

    // MARK: - Границы и стены

    func testAllItemsInsideRoomBounds() {
        let room = makeRoom()
        let items = [
            makeItem("диван", w: 2.2, h: 0.85, d: 0.95),
            makeItem("стол", w: 1.4, h: 0.75, d: 0.8),
            makeItem("шкаф", w: 1.8, h: 2.2, d: 0.6),
            makeItem("кресло", w: 0.8, h: 0.9, d: 0.8)
        ]

        let result = engine.arrange(items: items, room: room)
        let bounds = room.floorBounds

        XCTAssertFalse(result.placedItems.isEmpty)
        for item in result.placedItems {
            // Позиция — центр; след должен целиком лежать в комнате.
            XCTAssertGreaterThanOrEqual(item.position.x, bounds.minX, item.itemType)
            XCTAssertLessThanOrEqual(item.position.x, bounds.maxX, item.itemType)
            XCTAssertGreaterThanOrEqual(item.position.z, bounds.minZ, item.itemType)
            XCTAssertLessThanOrEqual(item.position.z, bounds.maxZ, item.itemType)
        }
    }

    func testWardrobePlacedAgainstWall() {
        let room = makeRoom()
        let result = engine.arrange(items: [makeItem("шкаф", w: 1.8, h: 2.2, d: 0.6)], room: room)

        XCTAssertEqual(result.placedItems.count, 1)
        let wardrobe = result.placedItems[0]
        let bounds = room.floorBounds

        // Задняя стенка шкафа — у одной из стен (зазор ≤ 15 см от края следа).
        let halfFootprint: Float = wardrobe.rotation == 90 || wardrobe.rotation == 270
            ? wardrobe.size.x / 2 : wardrobe.size.z / 2
        let distances = [
            wardrobe.position.z - halfFootprint - bounds.minZ,
            bounds.maxZ - (wardrobe.position.z + halfFootprint),
            wardrobe.position.x - halfFootprint - bounds.minX,
            bounds.maxX - (wardrobe.position.x + halfFootprint)
        ]
        XCTAssertLessThanOrEqual(distances.min() ?? 99, 0.15, "Шкаф должен стоять у стены")
    }

    // MARK: - Чистота результата (страховочный детектор согласен)

    func testEngineResultIsCleanByCollisionDetector() {
        let room = makeRoom()
        let items = [
            makeItem("диван", w: 2.2, h: 0.85, d: 0.95),
            makeItem("журнальный стол", w: 0.9, h: 0.45, d: 0.6),
            makeItem("шкаф", w: 1.5, h: 2.2, d: 0.6),
            makeItem("кресло", w: 0.8, h: 0.9, d: 0.8)
        ]

        let result = engine.arrange(items: items, room: room)
        let plan = RoomDesignPlan(
            items: result.placedItems,
            explanation: "",
            confidence: 1.0,
            providerName: "engine-test"
        )
        let report = CollisionDetector().check(plan: plan, room: room)

        XCTAssertTrue(report.collidingPairs.isEmpty, "Движок не должен давать пересечений")
        XCTAssertTrue(report.itemsOutOfBounds.isEmpty, "Движок не должен выходить за границы")
        XCTAssertTrue(report.blockedDoors.isEmpty, "Движок не должен блокировать двери")
    }

    // MARK: - Двери

    func testDoorZoneStaysFree() {
        let room = makeRoom()
        let door = room.doors[0]
        let clearance = Float(DesignNorms.doorClearanceFrontCm) / 100

        let items = [
            makeItem("диван", w: 2.0, h: 0.85, d: 0.9),
            makeItem("шкаф", w: 1.6, h: 2.2, d: 0.6)
        ]
        let result = engine.arrange(items: items, room: room)

        for item in result.placedItems {
            let dist = simd_length(item.position - door.position)
            XCTAssertGreaterThanOrEqual(
                dist, clearance,
                "«\(item.itemType)» стоит в зоне двери"
            )
        }
    }

    // MARK: - Парные правила

    func testNightstandPlacedNearBed() {
        let room = makeRoom(width: 4.0, depth: 3.5)
        let items = [
            makeItem("кровать", w: 1.6, h: 0.9, d: 2.0),
            makeItem("прикроватная тумбочка", w: 0.45, h: 0.5, d: 0.4)
        ]

        let result = engine.arrange(items: items, room: room)
        XCTAssertEqual(result.placedItems.count, 2)

        let bed = result.placedItems.first { $0.itemType.contains("кровать") }
        let nightstand = result.placedItems.first { $0.itemType.contains("тумбочка") }
        let dist = simd_length((bed?.position ?? .zero) - (nightstand?.position ?? .zero))
        XCTAssertLessThanOrEqual(dist, 1.6, "Тумбочка должна стоять рядом с кроватью")
    }

    func testCoffeeTableNearSofa() {
        let room = makeRoom()
        let items = [
            makeItem("диван", w: 2.2, h: 0.85, d: 0.95),
            makeItem("журнальный стол", w: 0.9, h: 0.45, d: 0.6)
        ]

        let result = engine.arrange(items: items, room: room)
        let sofa = result.placedItems.first { ArrangementCategory.from($0.itemType) == .sofa }
        let table = result.placedItems.first { ArrangementCategory.from($0.itemType) == .coffeeTable }

        XCTAssertNotNil(sofa)
        XCTAssertNotNil(table)
        let dist = simd_length((sofa?.position ?? .zero) - (table?.position ?? .zero))
        XCTAssertLessThanOrEqual(dist, 2.0, "Журнальный стол должен быть у дивана")
    }

    // MARK: - Переполнение

    func testOverfilledRoomReportsUnplaced() {
        let room = makeRoom(width: 2.5, depth: 2.0)
        let items = [
            makeItem("диван", w: 2.2, h: 0.85, d: 0.95),
            makeItem("кровать", w: 1.6, h: 0.9, d: 2.0),
            makeItem("шкаф", w: 1.8, h: 2.2, d: 0.6),
            makeItem("стол", w: 1.4, h: 0.75, d: 0.8)
        ]

        let result = engine.arrange(items: items, room: room)

        XCTAssertFalse(result.unplacedItems.isEmpty, "В комнате 2.5×2 не может поместиться всё")
        XCTAssertFalse(result.warnings.isEmpty, "Должно быть предупреждение о переполнении")
        // Размещённое и неразмещённое в сумме = вход.
        XCTAssertEqual(result.placedItems.count + result.unplacedItems.count, items.count)
    }

    // MARK: - FloorBounds

    func testFloorBoundsFromWalls() {
        let room = makeRoom(width: 5.0, depth: 3.0)
        let bounds = room.floorBounds
        XCTAssertEqual(bounds.width, 5.0, accuracy: 0.01)
        XCTAssertEqual(bounds.depth, 3.0, accuracy: 0.01)
    }

    func testFloorBoundsFallbackToSquare() {
        let room = RoomGeometry(
            area: 16.0,
            perimeter: 16.0,
            ceilingHeight: 2.7,
            walls: [],
            doors: [],
            windows: [],
            outlets: [],
            normalizedOrigin: .zero
        )
        let bounds = room.floorBounds
        XCTAssertEqual(bounds.width, 4.0, accuracy: 0.01)
        XCTAssertEqual(bounds.depth, 4.0, accuracy: 0.01)
    }

    // MARK: - Категории

    func testCategoryNormalizationRuEn() {
        XCTAssertEqual(ArrangementCategory.from("Диван угловой"), .sofa)
        XCTAssertEqual(ArrangementCategory.from("sofa"), .sofa)
        XCTAssertEqual(ArrangementCategory.from("Журнальный стол"), .coffeeTable)
        XCTAssertEqual(ArrangementCategory.from("прикроватная тумбочка"), .nightstand)
        XCTAssertEqual(ArrangementCategory.from("Тумба под ТВ"), .tvStand)
        XCTAssertEqual(ArrangementCategory.from("Шкаф-купе"), .wardrobe)
        XCTAssertEqual(ArrangementCategory.from("обеденный стол"), .table)
        XCTAssertEqual(ArrangementCategory.from("ковёр"), .rug)
        XCTAssertEqual(ArrangementCategory.from("кресло"), .armchair)
        XCTAssertEqual(ArrangementCategory.from("неизвестная штука"), .other)
    }
}
