import SwiftUI

@main
struct VO2CueApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.set(false, forKey: ReviewPromptPolicy.onboardingKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.purchases)
                .tint(.orange)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.activeRuntime?.update() }
                }
        }
    }
}
