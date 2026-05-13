// AIVibe
// Module: App
// Entry point. iOS 18 / Swift 6 App Lifecycle.

import SwiftUI

@main
struct AIVibeApp: App {

    init() {
        AppDependencies.configure()
    }

    var body: some Scene {
        WindowGroup {
            // TODO: Replace with full TabView / navigation once more features land
            RoomScanEntry()
        }
    }
}
