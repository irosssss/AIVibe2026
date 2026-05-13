// AIVibe
// Module: Features/RoomScan
// TCA 1.19+ / Swift 6 / iOS 18

import ComposableArchitecture
import Foundation

// MARK: - Scan Status

public enum ScanStatus: Equatable, Sendable {
    case idle
    case scanning
    case success
    case failure
}

// MARK: - RoomScanFeature

@Reducer
public struct RoomScanFeature: Sendable {

    // MARK: State

    @ObservableState
    public struct State: Equatable, Sendable {
        public var status: ScanStatus = .idle
        public var errorMessage: String? = nil

        public init() {}
    }

    // MARK: Action

    public enum Action: Sendable {
        case startScan
        case scanDidSucceed
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
                // TODO: запустить RoomPlanSession через Effect
                return .none

            case .scanDidSucceed:
                state.status = .success
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
