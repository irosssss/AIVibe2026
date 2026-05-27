// AIVibe/Features/RoomScan/RoomGeometryExtractor.swift
// Парсинг CapturedRoom (RoomPlan) в типизированную структуру RoomGeometry.

import Foundation
#if canImport(RoomPlan)
import RoomPlan
import simd
#endif

// MARK: - Типы геометрии (не зависят от RoomPlan)

public struct RoomGeometry: Codable, Sendable, Equatable {
    public let area: Double
    public let perimeter: Double
    public let ceilingHeight: Double
    public let walls: [WallGeometry]
    public let doors: [DoorGeometry]
    public let windows: [WindowGeometry]
    public let outlets: [OutletGeometry]
    public let normalizedOrigin: SIMD3<Float>

    public init(
        area: Double,
        perimeter: Double,
        ceilingHeight: Double,
        walls: [WallGeometry],
        doors: [DoorGeometry],
        windows: [WindowGeometry],
        outlets: [OutletGeometry],
        normalizedOrigin: SIMD3<Float>
    ) {
        self.area = area
        self.perimeter = perimeter
        self.ceilingHeight = ceilingHeight
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.outlets = outlets
        self.normalizedOrigin = normalizedOrigin
    }
}

public struct WallGeometry: Codable, Sendable, Equatable {
    public let start: SIMD3<Float>
    public let end: SIMD3<Float>
    public let length: Double
    public let height: Double
    public let isExterior: Bool
}

public struct DoorGeometry: Codable, Sendable, Equatable {
    public let position: SIMD3<Float>
    public let width: Double
    public let height: Double
    public let wallIndex: Int
}

public struct WindowGeometry: Codable, Sendable, Equatable {
    public let position: SIMD3<Float>
    public let width: Double
    public let height: Double
    public let sillHeight: Double
    public let wallIndex: Int
}

public struct OutletGeometry: Codable, Sendable, Equatable {
    public let position: SIMD3<Float>
    public let wallIndex: Int
}

// MARK: - Ошибки

public enum RoomGeometryError: LocalizedError, Sendable, Equatable {
    case noSurfaces
    case noFloorDetected
    case roomTooSmall(area: Double)
    case insufficientWalls(count: Int)

    public var errorDescription: String? {
        switch self {
        case .noSurfaces:
            return "Комната не содержит поверхностей"
        case .noFloorDetected:
            return "Не удалось определить пол комнаты"
        case .roomTooSmall(let area):
            return "Площадь \(String(format: "%.1f", area)) м² меньше минимальной (4 м²)"
        case .insufficientWalls(let count):
            return "Найдено \(count) стен, минимум — 3"
        }
    }
}

// MARK: - Протокол экстрактора

public protocol RoomGeometryExtracting: Sendable {
    #if canImport(RoomPlan)
    func extract(from capturedRoom: CapturedRoom) throws -> RoomGeometry
    #endif
}

// MARK: - Реализация (только с RoomPlan)

#if canImport(RoomPlan)

public struct RoomGeometryExtractor: RoomGeometryExtracting {

    public init() {}

    public func extract(from capturedRoom: CapturedRoom) throws -> RoomGeometry {
        let floors = capturedRoom.floors.filter { significantArea($0) }
        let wallSurfaces = capturedRoom.walls.filter { significantArea($0) }

        guard !floors.isEmpty else {
            if capturedRoom.walls.isEmpty && capturedRoom.floors.isEmpty {
                throw RoomGeometryError.noSurfaces
            }
            throw RoomGeometryError.noFloorDetected
        }

        guard wallSurfaces.count >= 3 else {
            throw RoomGeometryError.insufficientWalls(count: wallSurfaces.count)
        }

        let mainFloor = floors.max { surfaceArea($0) < surfaceArea($1) }!
        let area = surfaceArea(mainFloor)

        guard area >= 4.0 else {
            throw RoomGeometryError.roomTooSmall(area: area)
        }

        // Нормализуем координаты: нижний угол пола = (0,0,0)
        let floorPos = extractPosition(mainFloor.transform)
        let normalizedOrigin = floorPos

        // Высота потолка: оцениваем из максимальной высоты стен
        let ceilingHeight: Double = wallSurfaces
            .map { Double($0.dimensions.y) }
            .max() ?? 2.7

        // Стены
        let walls = wallSurfaces.map { surface -> WallGeometry in
            let pos = extractPosition(surface.transform) - normalizedOrigin
            let lengthAxis = SIMD3<Float>(
                surface.transform.columns.0.x,
                surface.transform.columns.0.y,
                surface.transform.columns.0.z
            )
            let halfLen = surface.dimensions.x / 2
            return WallGeometry(
                start: pos - lengthAxis * halfLen,
                end: pos + lengthAxis * halfLen,
                length: Double(surface.dimensions.x),
                height: Double(surface.dimensions.y),
                isExterior: false
            )
        }

        let perimeter = walls.reduce(0.0) { $0 + $1.length }

        // Двери
        let doors = capturedRoom.doors
            .filter { significantArea($0) }
            .map { surface -> DoorGeometry in
                let pos = extractPosition(surface.transform) - normalizedOrigin
                return DoorGeometry(
                    position: pos,
                    width: Double(surface.dimensions.x),
                    height: Double(surface.dimensions.y),
                    wallIndex: closestWallIndex(to: pos, in: walls)
                )
            }

        // Окна (порог sill: > 0.3 м от пола)
        let windows = capturedRoom.windows
            .filter { significantArea($0) }
            .map { surface -> WindowGeometry in
                let pos = extractPosition(surface.transform) - normalizedOrigin
                let sillY = Double(pos.y) - Double(surface.dimensions.y) / 2
                return WindowGeometry(
                    position: pos,
                    width: Double(surface.dimensions.x),
                    height: Double(surface.dimensions.y),
                    sillHeight: max(0, sillY),
                    wallIndex: closestWallIndex(to: pos, in: walls)
                )
            }

        return RoomGeometry(
            area: area,
            perimeter: perimeter,
            ceilingHeight: ceilingHeight,
            walls: walls,
            doors: doors,
            windows: windows,
            outlets: [],
            normalizedOrigin: normalizedOrigin
        )
    }

    // MARK: - Хелперы

    private func significantArea(_ surface: CapturedRoom.Surface) -> Bool {
        Double(surface.dimensions.x * surface.dimensions.y) >= 0.1
    }

    private func surfaceArea(_ surface: CapturedRoom.Surface) -> Double {
        Double(surface.dimensions.x * surface.dimensions.y)
    }

    private func extractPosition(_ transform: float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private func closestWallIndex(to position: SIMD3<Float>, in walls: [WallGeometry]) -> Int {
        var minDist = Float.infinity
        var result = 0
        for (i, wall) in walls.enumerated() {
            let center = (wall.start + wall.end) * 0.5
            let diff = position - center
            let dist = simd_length(diff)
            if dist < minDist {
                minDist = dist
                result = i
            }
        }
        return result
    }
}

#endif // canImport(RoomPlan)
