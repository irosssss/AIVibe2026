import Foundation
import Logging

// MARK: - Analytics Event

enum AnalyticsEvent {
    case aiRequestSent(provider: String)
    case aiRequestSuccess(provider: String, latencyMs: Int)
    case aiRequestFailed(provider: String, error: String)
    case aiFallbackTriggered(from: String, to: String)
    case roomScanStarted
    case roomScanCompleted(area: Float)
    case arObjectPlaced(objectType: String)
    case marketplaceItemTapped(store: String, price: Int)
    case portfolioItemViewed
}

// MARK: - Analytics Protocol

protocol AnalyticsProtocol {
    func track(event: AnalyticsEvent)
    func setUserProperty(_ value: String, forKey key: String)
}

// MARK: - AppMetrica Implementation

final class AppMetricaAnalytics: AnalyticsProtocol {
    private let logger = Logger(label: "ru.aivibe.app.analytics")

    func track(event: AnalyticsEvent) {
        // TODO: заменить Logger.log на AppMetrica.reportEvent(...) когда будет подключён SDK
        logger.info("Track: \(event)")
    }
    
    func setUserProperty(_ value: String, forKey key: String) {
        // TODO: заменить на AppMetrica.setUserProfileID / setUserProfileAttribute(...)
        logger.info("SetUserProperty: \(key) = \(value)")
    }
}

// MARK: - AnalyticsLogging (для AIProviderRouter)

extension AppMetricaAnalytics: AnalyticsLogging {
    func log(event: String, params: [String: any Sendable]) {
        track(event: .aiRequestSent(provider: event)) // упрощённое логирование
        logger.info("Track: \(event) — \(params)")
    }
}

// MARK: - Mock for Tests

final class MockAnalytics: AnalyticsProtocol {
    private let logger = Logger(label: "ru.aivibe.app.analytics")
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var userProperties: [String: String] = [:]
    
    func track(event: AnalyticsEvent) {
        trackedEvents.append(event)
        logger.info("Track: \(event)")
    }
    
    func setUserProperty(_ value: String, forKey key: String) {
        userProperties[key] = value
        logger.info("SetUserProperty: \(key) = \(value)")
    }
}
