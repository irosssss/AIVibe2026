import Foundation

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
    func track(event: AnalyticsEvent) {
        // TODO: заменить Logger.log на AppMetrica.reportEvent(...) когда будет подключён SDK
        #if DEBUG
        print("[AppMetrica] Track: \(event)")
        #endif
    }
    
    func setUserProperty(_ value: String, forKey key: String) {
        // TODO: заменить на AppMetrica.setUserProfileID / setUserProfileAttribute(...)
        #if DEBUG
        print("[AppMetrica] SetUserProperty: \(key) = \(value)")
        #endif
    }
}

// MARK: - Mock for Tests

final class MockAnalytics: AnalyticsProtocol {
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var userProperties: [String: String] = [:]
    
    func track(event: AnalyticsEvent) {
        trackedEvents.append(event)
        #if DEBUG
        print("[MockAnalytics] Track: \(event)")
        #endif
    }
    
    func setUserProperty(_ value: String, forKey key: String) {
        userProperties[key] = value
        #if DEBUG
        print("[MockAnalytics] SetUserProperty: \(key) = \(value)")
        #endif
    }
}
