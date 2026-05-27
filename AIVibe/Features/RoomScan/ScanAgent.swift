// AIVibe/Features/RoomScan/ScanAgent.swift
// Валидация качества LiDAR-скана перед запуском AI-пайплайна.

import Foundation
#if canImport(RoomPlan)
import RoomPlan
#endif
import Logging

// MARK: - Проблемы скана

public enum ScanIssue: Sendable, Equatable {
    case wallCompletenessLow(percent: Double)
    case roomTooSmall(area: Double)
    case noFloor
    case insufficientWalls(count: Int)
    case highNoise(outlierPercent: Double)
    case partialScan
}

// MARK: - Отчёт о качестве

public struct QualityReport: Sendable, Equatable {
    public let score: Double
    public let issues: [ScanIssue]
    public let canProceed: Bool

    public init(score: Double, issues: [ScanIssue]) {
        self.score = score
        self.issues = issues
        // Критические проблемы блокируют продолжение
        let hasCritical = issues.contains { issue in
            switch issue {
            case .roomTooSmall, .noFloor: return true
            default: return false
            }
        }
        self.canProceed = score >= 0.6 && !hasCritical
    }
}

// MARK: - Протокол

public protocol ScanAgentProtocol: Sendable {
    #if canImport(RoomPlan)
    func check(_ capturedRoom: CapturedRoom) async -> QualityReport
    #endif
}

// MARK: - Реализация

public actor ScanAgent: ScanAgentProtocol {

    private let extractor: any RoomGeometryExtracting
    private let logger = Logger(label: "ru.aivibe.scan-agent")

    public init(extractor: any RoomGeometryExtracting = RoomGeometryExtractor()) {
        self.extractor = extractor
    }

    #if canImport(RoomPlan)

    public func check(_ capturedRoom: CapturedRoom) async -> QualityReport {
        var score = 1.0
        var issues: [ScanIssue] = []

        let allSurfaces = capturedRoom.walls + capturedRoom.windows +
                          capturedRoom.doors + capturedRoom.openings
        let total = allSurfaces.count

        // Частичный скан: слишком мало поверхностей
        if total < 4 {
            issues.append(.partialScan)
            score -= 0.3
        }

        // Проверяем пол
        if capturedRoom.floors.isEmpty {
            issues.append(.noFloor)
            score = 0
        } else {
            // Площадь пола
            let floor = capturedRoom.floors.max {
                Double($0.dimensions.x * $0.dimensions.y) < Double($1.dimensions.x * $1.dimensions.y)
            }!
            let area = Double(floor.dimensions.x * floor.dimensions.y)

            if area < 4.0 {
                issues.append(.roomTooSmall(area: area))
                score = 0
            }
        }

        // Количество стен
        let wallCount = capturedRoom.walls.count
        if wallCount < 3 {
            let missing = 3 - wallCount
            issues.append(.insufficientWalls(count: wallCount))
            score -= Double(missing) * 0.2
        }

        // Полнота стен: доля поверхностей с высокой уверенностью
        if total > 0 {
            let highCount = allSurfaces.filter { $0.confidence == .high }.count
            let completeness = Double(highCount) / Double(total) * 100
            if completeness < 60 {
                issues.append(.wallCompletenessLow(percent: completeness))
                score -= 0.5
            } else if completeness < 80 {
                issues.append(.wallCompletenessLow(percent: completeness))
                score -= 0.3
            }

            // Шум: доля поверхностей с низкой уверенностью
            let lowCount = allSurfaces.filter { $0.confidence == .low }.count
            let noisePercent = Double(lowCount) / Double(total) * 100
            if noisePercent > 5 {
                issues.append(.highNoise(outlierPercent: noisePercent))
                score -= 0.1
            }
        }

        let finalScore = max(0.0, min(1.0, score))
        let report = QualityReport(score: finalScore, issues: issues)

        logger.info("Скан проверен: score=\(String(format: "%.2f", finalScore)), issues=\(issues.count), canProceed=\(report.canProceed)")
        return report
    }

    #endif // canImport(RoomPlan)
}
