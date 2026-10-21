import SwiftUI
import HealthKit
import WatchKit

@main
struct VO2CueWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self) private var appDelegate
    @State private var model = WatchAppModel.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .tint(.orange)
        }
    }
}

final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Starting is an acknowledged, expiring command over WatchConnectivity.
        // Waking the app alone must never start a default or stale profile.
        _ = WatchAppModel.shared
    }

    func handleActiveWorkoutRecovery() { WatchAppModel.shared.recoverActiveWorkout() }
}
