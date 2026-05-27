// AIVibe/Features/RoomScan/RoomScanFlowFeature.swift
// Flow-обёртка над существующим RoomScanFeature: добавляет 3 экрана —
// intro → scanning → result. Лежит рядом с RoomScanFeature, не задевая его.

import ComposableArchitecture
import Foundation

// MARK: - Domain DTO

public struct ScanResultObject: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String   // SF Symbol

    public init(id: UUID = UUID(), name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
    }
}

public struct RoomMetrics: Equatable, Sendable {
    public let area: String      // "18 м²"
    public let height: String    // "2.7 м"
    public let objectsCount: Int

    public init(area: String, height: String, objectsCount: Int) {
        self.area = area
        self.height = height
        self.objectsCount = objectsCount
    }

    public static let mock = RoomMetrics(area: "18 м²", height: "2.7 м", objectsCount: 5)
}

// MARK: - Phase

public enum RoomScanFlowPhase: Equatable, Sendable {
    case intro
    case scanning
    case result
}

// MARK: - Reducer

@Reducer
public struct RoomScanFlowFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var phase: RoomScanFlowPhase
        public var metrics: RoomMetrics
        public var detectedObjects: [ScanResultObject]
        public var rawScanData: Data?

        public init(
            phase: RoomScanFlowPhase = .intro,
            metrics: RoomMetrics = .mock,
            detectedObjects: [ScanResultObject] = RoomScanFlowFeature.mockObjects
        ) {
            self.phase = phase
            self.metrics = metrics
            self.detectedObjects = detectedObjects
            self.rawScanData = nil
        }
    }

    public enum Action: Sendable {
        case startScanTapped
        case scanFinished(Data)
        case scanFailed(String)
        case closeTapped
        case manualEntryTapped
        case rescanTapped
        case continueTapped
        case backFromResultTapped
        case editObjectTapped(ScanResultObject.ID)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startScanTapped:
                state.phase = .scanning
                return .none

            case let .scanFinished(data):
                state.phase = .result
                state.rawScanData = data
                return .none

            case .scanFailed:
                // На MVP — возврат в intro. В будущем — отдельный error-screen.
                state.phase = .intro
                return .none

            case .rescanTapped:
                state.phase = .scanning
                return .none

            case .backFromResultTapped:
                state.phase = .intro
                return .none

            case .closeTapped,
                 .manualEntryTapped,
                 .continueTapped,
                 .editObjectTapped:
                // Делегируется наверх (App-shell — pop / push).
                return .none
            }
        }
    }

    public static let mockObjects: [ScanResultObject] = [
        .init(name: "Окно",     icon: "square.split.2x1"),
        .init(name: "Дверь",    icon: "door.left.hand.closed"),
        .init(name: "Радиатор", icon: "thermometer.medium"),
        .init(name: "Шкаф",     icon: "cube"),
        .init(name: "Стол",     icon: "cube")
    ]
}
