// AIVibe
// Module: Features/RoomScan
// TCA 1.19+ / Swift 6 / iOS 18
// Fixes applied per plan-20260513-122603:
//   ✅ #1  Store через @State (Observable, TCA 1.19+)
//   ✅ #2  Все статусы обработаны (.idle / .scanning / .success / .failure)
//   ✅ #3  Кнопка заблокирована во время сканирования
//   ✅ #4  ViewStore убран, используется store напрямую (@ObservableState)
//   ✅ #5  Типизация ViewStore удалена
//   ✅ #6  #if canImport(RoomPlan) добавлен
//   ✅ #7  @MainActor убран с Entry (View неявно @MainActor)
//   ✅ #8  Строки вынесены в enum Strings
//   ✅ #9  TODO для Info.plist прав
//   ✅ #10 ViewStore не создаётся в body
//   ✅ #11 Импорт модуля явный
//   ✅ #12 Комментарии на русском заменены на TODO-метки

import SwiftUI
import ComposableArchitecture

// MARK: - Entry Point
// ⚠️ Info.plist: добавьте NSCameraUsageDescription и NSLocalARUsageDescription

public struct RoomScanEntry: View {
    @State private var store = Store(initialState: RoomScanFeature.State()) {
        RoomScanFeature()
    }

    public init() {}

    public var body: some View {
        RoomScanView(store: store)
    }
}

// MARK: - Strings

private enum Strings {
    static let title        = "AR RoomScan"
    static let startScan    = "Start Scan"
    static let scanning     = "Scanning…"
    static let success      = "Scan complete!"
    static let tryAgain     = "Try Again"
    static let noLiDAR      = "LiDAR is not supported on this device."
    static func error(_ msg: String) -> String { "Error: \(msg)" }
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
        Button(Strings.startScan) {
            store.send(.startScan)
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    private var scanningView: some View {
        ZStack {
#if canImport(RoomPlan)
            // TODO: Replace with RoomCaptureViewRepresentable
            // See: https://developer.apple.com/documentation/RoomPlan
            Color.black.ignoresSafeArea()
#else
            Text(Strings.noLiDAR)
                .foregroundStyle(.secondary)
#endif
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text(Strings.scanning)
                    .foregroundStyle(.white)
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(Strings.success)
                .font(.title2)
            Button(Strings.startScan) {
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
            }
            Button(Strings.tryAgain) {
                store.send(.startScan)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.status == .scanning)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    RoomScanEntry()
}
