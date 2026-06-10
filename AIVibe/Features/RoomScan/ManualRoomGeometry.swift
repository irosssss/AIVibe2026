// AIVibe/Features/RoomScan/ManualRoomGeometry.swift
// Построение RoomGeometry из ручного ввода размеров — путь без LiDAR (массовый рынок РФ).
// Прямоугольная комната: ширина (ось x) × глубина (ось z) × высота потолка (ось y).
// Переиспользует существующий тип RoomGeometry и порог 4 м² из RoomGeometryError.roomTooSmall.
// См. docs/UPGRADE_PLAN.md — Фаза 1, блок A1.

import Foundation
import simd

extension RoomGeometry {

    /// Допустимые диапазоны ручного ввода (в метрах). Используются и формой, и валидацией.
    public enum ManualBounds {
        /// Ширина и глубина комнаты.
        public static let side: ClosedRange<Double> = 1.0...30.0
        /// Высота потолка.
        public static let height: ClosedRange<Double> = 2.0...5.0
        /// Минимальная площадь — синхронизирована с RoomGeometryError.roomTooSmall.
        public static let minArea: Double = 4.0
    }

    /// Проверяет, что размеры прямоугольной комнаты в допустимых диапазонах и площадь ≥ 4 м².
    /// Используется формой для блокировки кнопки «Продолжить».
    public static func isValidManualRoom(widthM w: Double, depthM d: Double, heightM h: Double) -> Bool {
        ManualBounds.side.contains(w)
            && ManualBounds.side.contains(d)
            && ManualBounds.height.contains(h)
            && (w * d) >= ManualBounds.minArea
    }

    /// Строит геометрию прямоугольной комнаты из ручных размеров (в метрах).
    /// Пол на y = 0, начало координат — в углу (0,0,0); 4 стены против часовой стрелки.
    /// Двери/окна/розетки не задаются (ручной ввод их не собирает) — downstream-инструменты
    /// работают и без них (нет ограничений по проёмам).
    /// - Throws: `RoomGeometryError.roomTooSmall`, если площадь < 4 м².
    public static func manualRectangular(widthM w: Double, depthM d: Double, heightM h: Double) throws -> RoomGeometry {
        let area = w * d
        guard area >= ManualBounds.minArea else {
            throw RoomGeometryError.roomTooSmall(area: area)
        }

        let fw = Float(w), fd = Float(d)
        // Углы пола по часовой стрелке от начала координат.
        let corner0 = SIMD3<Float>(0, 0, 0)
        let corner1 = SIMD3<Float>(fw, 0, 0)
        let corner2 = SIMD3<Float>(fw, 0, fd)
        let corner3 = SIMD3<Float>(0, 0, fd)

        let walls: [WallGeometry] = [
            WallGeometry(start: corner0, end: corner1, length: w, height: h, isExterior: false),
            WallGeometry(start: corner1, end: corner2, length: d, height: h, isExterior: false),
            WallGeometry(start: corner2, end: corner3, length: w, height: h, isExterior: false),
            WallGeometry(start: corner3, end: corner0, length: d, height: h, isExterior: false)
        ]

        return RoomGeometry(
            area: area,
            perimeter: 2 * (w + d),
            ceilingHeight: h,
            walls: walls,
            doors: [],
            windows: [],
            outlets: [],
            normalizedOrigin: SIMD3<Float>(0, 0, 0)
        )
    }
}
