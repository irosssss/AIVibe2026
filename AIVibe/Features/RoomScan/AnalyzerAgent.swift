// AIVibe/Features/RoomScan/AnalyzerAgent.swift
// Обёртка над RoomGeometryExtractor с аналитикой и логированием.

import Foundation
import RoomPlan
import Logging

// MARK: - Протокол

public protocol AnalyzerAgentProtocol: Sendable {
    func extract(_ capturedRoom: CapturedRoom) async throws -> RoomGeometry
}

// MARK: - Реализация

public actor AnalyzerAgent: AnalyzerAgentProtocol {

    private let extractor: any RoomGeometryExtracting
    private let analytics: any AnalyticsLogging
    private let logger = Logger(label: "ru.aivibe.analyzer-agent")

    public init(
        extractor: any RoomGeometryExtracting = RoomGeometryExtractor(),
        analytics: any AnalyticsLogging = NoopAnalytics()
    ) {
        self.extractor = extractor
        self.analytics = analytics
    }

    public func extract(_ capturedRoom: CapturedRoom) async throws -> RoomGeometry {
        let start = Date()

        do {
            let geometry = try extractor.extract(from: capturedRoom)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)

            analytics.log(event: "room_analyzed", params: [
                "area": geometry.area,
                "wall_count": geometry.walls.count,
                "door_count": geometry.doors.count,
                "window_count": geometry.windows.count,
                "duration_ms": durationMs
            ])

            logger.info("Геометрия извлечена: \(String(format: "%.1f", geometry.area)) м², \(geometry.walls.count) стен, за \(durationMs) мс")
            return geometry

        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            analytics.log(event: "room_analysis_failed", params: [
                "error": error.localizedDescription,
                "duration_ms": durationMs
            ])
            logger.error("Ошибка извлечения геометрии: \(error.localizedDescription)")
            throw error
        }
    }
}
