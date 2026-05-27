// AIVibe
// Module: Features/RoomScan
// TCA 1.19+ / Swift 6 / iOS 18

import ComposableArchitecture
import Foundation
#if canImport(RoomPlan)
import RoomPlan
#endif

// MARK: - Scan Status

public enum ScanStatus: Equatable, Sendable {
    case idle
    case scanning
    case success(data: Data)
    case failure
}

// MARK: - RoomScanFeature

@Reducer
public struct RoomScanFeature: Sendable {

    // MARK: State

    @ObservableState
    public struct State: Equatable, Sendable {
        public var status: ScanStatus = .idle
        public var errorMessage: String?

        public init() {}
    }

    // MARK: Action

    public enum Action: Sendable {
        case startScan
        case stopScan
        case scanDidSucceed(Data)
        case scanDidFail(String)
        case resetScan
    }

    // MARK: Init

    public init() {}

    // MARK: Body

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .startScan:
                guard state.status != .scanning else { return .none }
                state.status = .scanning
                state.errorMessage = nil
                return .none

            case .stopScan:
                guard state.status == .scanning else { return .none }
                state.status = .idle
                state.errorMessage = nil
                return .run { _ in
                    await RoomScanSession.shared.stop()
                }

            case .scanDidSucceed(let data):
                state.status = .success(data: data)
                return .none

            case .scanDidFail(let message):
                state.status = .failure
                state.errorMessage = message
                return .none

            case .resetScan:
                state.status = .idle
                state.errorMessage = nil
                return .none
            }
        }
    }
}

// MARK: - RoomScanSession (shared session controller)

/// Actor that owns the RoomCaptureSession instance so it can be stopped from the reducer effect.
/// The Coordinator in RoomScanView registers its session here on creation.
public actor RoomScanSession {
    public static let shared = RoomScanSession()

    #if canImport(RoomPlan)
    private weak var activeSession: RoomCaptureSession?
    private var lastCapturedRoom: CapturedRoom?

    public func register(_ session: RoomCaptureSession) {
        activeSession = session
    }

    public func stop() {
        activeSession?.stop()
        activeSession = nil
    }

    public func storeCapturedRoom(_ room: CapturedRoom) {
        lastCapturedRoom = room
    }

    public func checkQuality() async -> QualityReport {
        guard let room = lastCapturedRoom else {
            return QualityReport(score: 0, issues: [.noFloor])
        }
        return await ScanAgent().check(room)
    }

    public func extractGeometry() async throws -> RoomGeometry {
        guard let room = lastCapturedRoom else {
            throw RoomGeometryError.noSurfaces
        }
        return try await AnalyzerAgent().extract(room)
    }
    #else
    public func register(_ session: Any) {}
    public func stop() {}

    public func checkQuality() async -> QualityReport {
        QualityReport(score: 0, issues: [.partialScan])
    }

    public func extractGeometry() async throws -> RoomGeometry {
        throw RoomGeometryError.noSurfaces
    }
    #endif
}
