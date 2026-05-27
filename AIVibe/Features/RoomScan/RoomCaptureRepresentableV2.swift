// AIVibe/Features/RoomScan/RoomCaptureRepresentableV2.swift
// Версия 2: добавлен RoomCaptureSessionDelegate для real-time прогресса.
// Существующий RoomCaptureRepresentable из RoomScanView.swift не трогаем —
// он используется в legacy `RoomScanEntry`.

import SwiftUI

#if canImport(RoomPlan)
import RoomPlan

/// Не-Sendable обёртка для передачи в actor (наследие из v1).
private struct SessionBox: @unchecked Sendable { let value: RoomCaptureSession }

struct RoomCaptureRepresentableV2: UIViewRepresentable {

    let progress: RoomScanProgress
    let onCapturedRoom: @Sendable (CapturedRoom) -> Void
    let onError: @Sendable (Error) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        context.coordinator.assignSession(view.captureSession)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        context.coordinator.startIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            progress: progress,
            onCapturedRoom: onCapturedRoom,
            onError: onError
        )
    }

    @objc(RoomCaptureV2Coordinator)
    class Coordinator: NSObject,
                       RoomCaptureViewDelegate,
                       RoomCaptureSessionDelegate,
                       NSCoding {

        private var session: RoomCaptureSession!
        private let progress: RoomScanProgress
        private let onCapturedRoom: @Sendable (CapturedRoom) -> Void
        private let onError: @Sendable (Error) -> Void
        private var didStart = false

        init(
            progress: RoomScanProgress,
            onCapturedRoom: @escaping @Sendable (CapturedRoom) -> Void,
            onError: @escaping @Sendable (Error) -> Void
        ) {
            self.progress = progress
            self.onCapturedRoom = onCapturedRoom
            self.onError = onError
        }

        func encode(with coder: NSCoder) {}
        required init?(coder: NSCoder) { return nil }

        func assignSession(_ session: RoomCaptureSession) {
            self.session = session
            session.delegate = self
        }

        func startIfNeeded() {
            guard !didStart, let session else { return }
            didStart = true
            let box = SessionBox(value: session)
            Task {
                await RoomScanSession.shared.register(box.value)
            }
            let config = RoomCaptureSession.Configuration()
            session.run(configuration: config)
        }

        // MARK: - RoomCaptureSessionDelegate (real-time updates)

        func captureSession(_ session: RoomCaptureSession,
                            didUpdate room: CapturedRoom) {
            let walls   = room.walls.count
            let objects = room.objects.count
            let windows = room.windows.count
            let doors   = room.doors.count

            // confidenceHigh — доля surfaces с .high уверенностью.
            let allSurfaces: [CapturedRoom.Surface] = room.walls + room.windows + room.doors + room.openings
            let total = allSurfaces.count
            let highCount = allSurfaces.filter { $0.confidence == .high }.count
            let highRatio = total > 0 ? Double(highCount) / Double(total) : 0

            // Captured как локальная let, чтобы Task не захватывал `self`
            // (Coordinator: NSObject — не Sendable в Swift 6 strict).
            let progressRef = progress
            Task { @MainActor in
                progressRef.update(
                    walls: walls,
                    objects: objects,
                    windows: windows,
                    doors: doors,
                    confidenceHigh: highRatio
                )
            }
        }

        func captureSession(_ session: RoomCaptureSession,
                            didProvide instruction: RoomCaptureSession.Instruction) {
            let text = instruction.localizedRu
            let progressRef = progress
            Task { @MainActor in
                progressRef.setInstruction(text)
            }
        }

        func captureSession(_ session: RoomCaptureSession,
                            didEndWith data: CapturedRoomData,
                            error: Error?) {
            if let error {
                onError(error)
            }
        }

        // MARK: - RoomCaptureViewDelegate (finalize)

        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                         error: (any Error)?) -> Bool {
            if let error {
                onError(error)
                return false
            }
            return true
        }

        func captureView(didPresent processedResult: CapturedRoom,
                         error: (any Error)?) {
            if let error {
                onError(error)
            } else {
                onCapturedRoom(processedResult)
            }
        }
    }
}
#endif
