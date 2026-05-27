// AIVibe/Features/RoomScan/RoomScanProgress.swift
// Observable модель прогресса сканирования. Обновляется RoomCaptureSession
// delegate'ом в реальном времени. На симуляторе — таймером (fallback).
//
// Прогресс — proxy: RoomPlan не отдаёт «% покрытия», поэтому считаем по
// найденным surfaces:
//   walls    : вес 0.5  (типовая комната — 4 стены)
//   objects  : вес 0.3  (мебель, окна, двери)
//   confidence: вес 0.2  (доля high-confidence surfaces)
//
// Auto-stop при `progress >= autoStopThreshold` (0.92) + наличии минимум
// 3 стен и 1 объекта.

import Foundation
import Observation

#if canImport(RoomPlan)
import RoomPlan
#endif

@MainActor
@Observable
public final class RoomScanProgress {

    // MARK: - Public progress

    public private(set) var progress: Double = 0    // 0…1
    public private(set) var wallsCount: Int = 0
    public private(set) var objectsCount: Int = 0
    public private(set) var windowsCount: Int = 0
    public private(set) var doorsCount: Int = 0
    public private(set) var instruction: String?    // подсказка пользователю
    public private(set) var isComplete: Bool = false

    // MARK: - Config

    public let autoStopThreshold: Double = 0.92
    public let minWallsForComplete: Int = 3
    public let minObjectsForComplete: Int = 1

    public init() {}

    // MARK: - Updates (вызываются из Coordinator delegate)

    public func update(walls: Int, objects: Int, windows: Int, doors: Int, confidenceHigh: Double) {
        wallsCount = walls
        objectsCount = objects
        windowsCount = windows
        doorsCount = doors

        let wallScore   = min(Double(walls) / 4.0, 1.0)
        let objectScore = min(Double(objects + windows + doors) / 4.0, 1.0)

        progress = min(wallScore * 0.5 + objectScore * 0.3 + confidenceHigh * 0.2, 1.0)

        if walls >= minWallsForComplete
            && objects >= minObjectsForComplete
            && progress >= autoStopThreshold {
            isComplete = true
        }
    }

    public func setInstruction(_ text: String?) {
        instruction = text
    }

    public func reset() {
        progress = 0
        wallsCount = 0
        objectsCount = 0
        windowsCount = 0
        doorsCount = 0
        instruction = nil
        isComplete = false
    }
}

// MARK: - User-facing instructions

#if canImport(RoomPlan)
extension RoomCaptureSession.Instruction {
    /// Локализованный текст для overlay подсказки.
    var localizedRu: String {
        switch self {
        case .moveCloseToWall:       return "Подойдите ближе к стене"
        case .moveAwayFromWall:      return "Отойдите от стены"
        case .slowDown:              return "Двигайтесь медленнее"
        case .turnOnLight:           return "Включите свет"
        case .normal:                return "Продолжайте сканировать"
        case .lowTexture:            return "Недостаточно деталей — направьте камеру на текстурную поверхность"
        @unknown default:            return "Продолжайте сканировать"
        }
    }
}
#endif
