// AIVibe
// Module: Features/RoomScan
// TCA 1.19+ / Swift 6 / iOS 18

import SwiftUI
import ComposableArchitecture

// MARK: - Strings

private enum Strings {
    static let title        = "AR RoomScan"
    static let startScan    = "Start Scan"
    static let stopScan     = "Stop Scan"
    static let scanning     = "Scanning…"
    static let success      = "Scan complete!"
    static let tryAgain     = "Try Again"
    static let reset        = "Scan Again"
    static let noLiDAR      = "LiDAR scanner is not available on this device."
    static let placeholder  = "Tap Start to begin scanning the room."
    static func error(_ msg: String) -> String { "Error: \(msg)" }
}

// MARK: - Entry Point

public struct RoomScanEntry: View {
    @State private var store = Store(initialState: RoomScanFeature.State()) {
        RoomScanFeature()
    }

    public init() {}

    public var body: some View {
        RoomScanView(store: store)
    }
}

// MARK: - Main View

struct RoomScanView: View {
    let store: StoreOf<RoomScanFeature>

    var body: some View {
        NavigationStack {
            Group {
                switch store.status {
                case .idle:
                    idleView
                case .scanning:
                    scanningView
                case .success:
                    successView
                case .failure:
                    failureView
                }
            }
            .navigationTitle(Strings.title)
        }
    }

    // MARK: Sub-views

    private var idleView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(Strings.placeholder)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button(Strings.startScan) {
                store.send(.startScan)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var scanningView: some View {
#if canImport(RoomPlan)
        RoomCaptureRepresentable(
            onCapturedRoom: { capturedRoom in
                // CapturedRoom is not Encodable; export via USDZ.
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("room_scan_\(UUID().uuidString).usdz")
                do {
                    try capturedRoom.export(to: tempURL)
                    let data = try Data(contentsOf: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)
                    store.send(.scanDidSucceed(data))
                } catch {
                    store.send(.scanDidFail("USDZ export failed: \(error.localizedDescription)"))
                }
            },
            onError: { error in
                store.send(.scanDidFail(error.localizedDescription))
            }
        )
        .overlay(alignment: .bottom) {
            Button(Strings.stopScan) {
                store.send(.stopScan)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding()
        }
        .ignoresSafeArea()
#else
        ZStack {
            Color(.systemGray6).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(Strings.noLiDAR)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
#endif
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(Strings.success)
                .font(.title2)

            Button(Strings.reset) {
                store.send(.resetScan)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var failureView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            if let message = store.errorMessage {
                Text(Strings.error(message))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            Button(Strings.tryAgain) {
                store.send(.startScan)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - RoomCapture ViewRepresentable (RoomPlan)

#if canImport(RoomPlan)
import RoomPlan

struct RoomCaptureRepresentable: UIViewRepresentable {
    let onCapturedRoom: @Sendable (CapturedRoom) -> Void
    let onError: @Sendable (Error) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession = context.coordinator.session
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        // start the session when view appears
        context.coordinator.startIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCapturedRoom: onCapturedRoom,
            onError: onError
        )
    }

    class Coordinator: NSObject, RoomCaptureViewDelegate {

        // MARK: Session

        let session = RoomCaptureSession()

        // MARK: Callbacks

        private let onCapturedRoom: @Sendable (CapturedRoom) -> Void
        private let onError: @Sendable (Error) -> Void

        // MARK: State

        private var didStart = false

        init(
            onCapturedRoom: @escaping @Sendable (CapturedRoom) -> Void,
            onError: @escaping @Sendable (Error) -> Void
        ) {
            self.onCapturedRoom = onCapturedRoom
            self.onError = onError
        }

        func startIfNeeded() {
            guard !didStart else { return }
            didStart = true
            // Register session so reducer can stop it
            Task { await RoomScanSession.shared.register(session) }
            let config = RoomCaptureSession.Configuration()
            session.run(configuration: config)
        }

        // MARK: RoomCaptureViewDelegate

        func captureView(
            shouldPresentRoomDataFor capturingData: RoomCaptureView.CapturingData
        ) -> Bool {
            true
        }

        func captureView(
            _ captureView: RoomCaptureView,
            didPresent processedRoom: CapturedRoom
        ) {
            onCapturedRoom(processedRoom)
        }

        func captureView(
            _ captureView: RoomCaptureView,
            didErrorWith error: Error
        ) {
            onError(error)
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    RoomScanEntry()
}