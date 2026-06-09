// AIVibe/Features/RoomScan/RoomScanFlowFeature.swift
// Flow-обёртка над существующим RoomScanFeature: добавляет 3 экрана —
// intro → scanning → result. Лежит рядом с RoomScanFeature, не задевая его.

import ComposableArchitecture
import Foundation
import Logging

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
    case manualEntry
    case scanning
    case result
    case styleSelection
    case generating
    case designComplete
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
        public var qualityReport: QualityReport?
        public var geometry: RoomGeometry?
        public var designPreferences: UserDesignPreferences?
        public var isGeneratingDesign: Bool = false
        public var designPlan: RoomDesignPlan?
        public var designError: String?
        /// Ошибка валидации ручного ввода размеров (путь без LiDAR).
        public var manualEntryError: String?
        /// Статус подписки — для гейтинга квоты сканов FREE (A3.3, UPGRADE_PLAN).
        public var subscriptionStatus: SubscriptionStatus = .free
        /// Не-nil → поверх флоу показывается пейволл.
        public var paywallTrigger: PaywallTrigger?

        public init(
            phase: RoomScanFlowPhase = .intro,
            metrics: RoomMetrics = .mock,
            detectedObjects: [ScanResultObject] = RoomScanFlowFeature.mockObjects
        ) {
            self.phase = phase
            self.metrics = metrics
            self.detectedObjects = detectedObjects
        }
    }

    public enum Action: Sendable {
        case flowAppeared
        case subscriptionStatusLoaded(SubscriptionStatus)
        case paywallDismissed
        case startScanTapped
        case scanFinished(Data)
        case scanFailed(String)
        case closeTapped
        case manualEntryTapped
        case manualDimensionsSubmitted(widthM: Double, depthM: Double, heightM: Double)
        case backFromManualEntryTapped
        case rescanTapped
        case continueTapped
        case backFromResultTapped
        case editObjectTapped(ScanResultObject.ID)
        // Пайплайн дизайна
        case qualityReportReceived(QualityReport)
        case geometryExtracted(RoomGeometry)
        case selectStyleTapped
        case preferencesSet(UserDesignPreferences)
        case generateDesignTapped
        case designGenerated(RoomDesignPlan)
        case designGenerationFailed(String)
        case backFromStyleTapped
    }

    @Dependency(\.agentOrchestrator) var agentOrchestrator
    @Dependency(\.subscriptionClient) var subscriptionClient
    @Dependency(\.storageClient) var storageClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .flowAppeared:
                return .run { send in
                    let status = await subscriptionClient.fetchStatus()
                    await send(.subscriptionStatusLoaded(status))
                }

            case let .subscriptionStatusLoaded(status):
                state.subscriptionStatus = status
                return .none

            case .paywallDismissed:
                state.paywallTrigger = nil
                return .none

            case .startScanTapped:
                // Гейт квоты FREE (3 скана/мес — STRATEGY §1.3). PRO/BUSINESS — безлимит.
                guard quotaAllowsScan(&state) else { return .none }
                // Квота списывается на старте (просто и детерминированно для MVP).
                // rescanTapped квоту НЕ тратит — это повтор той же сессии.
                consumeScanQuota()
                state.phase = .scanning
                return .none

            case let .scanFinished(data):
                state.phase = .result
                state.rawScanData = data
                return .run { send in
                    let quality = await RoomScanSession.shared.checkQuality()
                    await send(.qualityReportReceived(quality))
                    if quality.canProceed {
                        if let geometry = try? await RoomScanSession.shared.extractGeometry() {
                            await send(.geometryExtracted(geometry))
                        }
                    }
                }

            case .scanFailed:
                state.phase = .intro
                return .none

            case .rescanTapped:
                state.phase = .scanning
                state.qualityReport = nil
                state.geometry = nil
                state.designPlan = nil
                state.designError = nil
                return .none

            case .backFromResultTapped:
                state.phase = .intro
                return .none

            case let .qualityReportReceived(report):
                state.qualityReport = report
                return .none

            case let .geometryExtracted(geometry):
                state.geometry = geometry
                state.metrics = RoomMetrics(
                    area: String(format: "%.0f м²", geometry.area),
                    height: String(format: "%.1f м", geometry.ceilingHeight),
                    objectsCount: geometry.doors.count + geometry.windows.count
                )
                return .none

            case .selectStyleTapped:
                state.phase = .styleSelection
                return .none

            case let .preferencesSet(prefs):
                state.designPreferences = prefs
                return .none

            case .generateDesignTapped:
                guard let geometry = state.geometry,
                      let prefs = state.designPreferences else { return .none }
                state.phase = .generating
                state.isGeneratingDesign = true
                state.designError = nil
                return .run { send in
                    do {
                        let plan = try await agentOrchestrator.generateDesign(
                            geometry: geometry,
                            preferences: prefs
                        )
                        await send(.designGenerated(plan))
                    } catch {
                        await send(.designGenerationFailed(error.localizedDescription))
                    }
                }

            case let .designGenerated(plan):
                state.isGeneratingDesign = false
                state.designPlan = plan
                state.phase = .designComplete
                return .none

            case let .designGenerationFailed(msg):
                state.isGeneratingDesign = false
                state.designError = msg
                state.phase = .styleSelection
                return .none

            case .backFromStyleTapped:
                state.phase = .result
                return .none

            case .manualEntryTapped:
                // Ручной ввод — тоже «скан» (ведёт к той же AI-генерации): без гейта
                // путь без LiDAR (основной для массовых устройств, A1.3) обходил бы пейволл.
                // Здесь только проверка (без списания) — чтобы не дать зря заполнять форму.
                guard quotaAllowsScan(&state) else { return .none }
                state.manualEntryError = nil
                state.phase = .manualEntry
                return .none

            case let .manualDimensionsSubmitted(width, depth, height):
                do {
                    let geometry = try RoomGeometry.manualRectangular(
                        widthM: width, depthM: depth, heightM: height
                    )
                    // Списание — при успешном вводе (аналог старта AR-скана).
                    guard quotaAllowsScan(&state) else { return .none }
                    consumeScanQuota()
                    state.manualEntryError = nil
                    state.phase = .styleSelection
                    // Переиспользуем путь LiDAR-скана: .geometryExtracted выставит geometry + metrics.
                    return .send(.geometryExtracted(geometry))
                } catch {
                    state.manualEntryError = error.localizedDescription
                    return .none
                }

            case .backFromManualEntryTapped:
                state.manualEntryError = nil
                state.phase = .intro
                return .none

            case .closeTapped,
                 .continueTapped,
                 .editObjectTapped:
                return .none
            }
        }
    }

    // MARK: - Гейт квоты сканов (A3.3, UPGRADE_PLAN)

    /// Проверяет квоту FREE; при исчерпании показывает пейволл (`paywallTrigger = .scanLimit`).
    /// PRO/BUSINESS — безлимит. Возвращает true, если действие можно продолжать.
    private func quotaAllowsScan(_ state: inout State) -> Bool {
        let quota = ScanQuota.load(from: storageClient)
        guard quota.canStartScan(tier: state.subscriptionStatus.effectiveTier) else {
            state.paywallTrigger = .scanLimit
            return false
        }
        return true
    }

    /// Списывает один скан из месячной квоты.
    private func consumeScanQuota() {
        ScanQuota.load(from: storageClient).afterScan().save(to: storageClient)
    }

    public static let mockObjects: [ScanResultObject] = [
        .init(name: "Окно", icon: "square.split.2x1"),
        .init(name: "Дверь", icon: "door.left.hand.closed"),
        .init(name: "Радиатор", icon: "thermometer.medium"),
        .init(name: "Шкаф", icon: "cube"),
        .init(name: "Стол", icon: "cube")
    ]
}
