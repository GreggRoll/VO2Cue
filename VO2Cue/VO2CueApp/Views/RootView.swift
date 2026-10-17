import SwiftUI
import StoreKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReviewPromptPolicy.onboardingKey) private var hasCompletedOnboarding = false
    @State private var reviewTask: Task<Void, Never>?

    var body: some View {
        @Bindable var model = model

        Group {
            if !hasCompletedOnboarding {
                WelcomeView { hasCompletedOnboarding = true }
            } else if !purchases.isUnlocked {
                PaywallView(onReviewIntroduction: { hasCompletedOnboarding = false })
            } else if #available(iOS 18.0, *) {
                TabView(selection: $model.selectedTab) {
                    Tab("Workouts", systemImage: "figure.run", value: AppTab.workouts) {
                        WorkoutsView()
                    }
                    Tab("Progress", systemImage: "chart.bar", value: AppTab.progress) {
                        TrainingProgressView()
                    }
                    Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                        SettingsView()
                    }
                }
            } else {
                TabView(selection: $model.selectedTab) {
                    WorkoutsView()
                        .tabItem { Label("Workouts", systemImage: "figure.run") }
                        .tag(AppTab.workouts)
                    TrainingProgressView()
                        .tabItem { Label("Progress", systemImage: "chart.bar") }
                        .tag(AppTab.progress)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            }
        }
        .fullScreenCover(item: $model.activeRuntime, onDismiss: workoutDismissed) { runtime in
            WorkoutRuntimeView(runtime: runtime)
                .environment(model)
        }
        .task {
            guard !isUnitTestHost else { return }
            await purchases.start()
            model.syncPurchaseAccess()
            model.startPendingWidgetWorkout(hasCompletedOnboarding: hasCompletedOnboarding)
        }
        .onChange(of: purchases.watchAccess) { _, _ in
            model.syncPurchaseAccess()
            model.startPendingWidgetWorkout(hasCompletedOnboarding: hasCompletedOnboarding)
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            model.startPendingWidgetWorkout(hasCompletedOnboarding: completed)
        }
        .onOpenURL { url in
            model.handleWidgetURL(url)
            Task {
                await purchases.refreshAccess()
                model.startPendingWidgetWorkout(hasCompletedOnboarding: hasCompletedOnboarding)
            }
        }
        .onChange(of: model.reminders.openWorkoutsRequested, initial: true) { _, requested in
            if requested {
                model.selectedTab = .workouts
                model.workoutsNavigationPath.removeAll()
                model.reminders.openWorkoutsRequested = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                reviewTask?.cancel()
            } else if !isUnitTestHost {
                Task {
                    await purchases.refreshAccess()
                    model.syncPurchaseAccess()
                    model.refreshWidgets()
                    model.startPendingWidgetWorkout(hasCompletedOnboarding: hasCompletedOnboarding)
                    await model.reminders.refreshAuthorization()
                }
            }
        }
        .onDisappear { reviewTask?.cancel() }
    }

    private var isUnitTestHost: Bool {
        #if DEBUG
        // Hosted unit tests start StoreKit explicitly after creating SKTestSession.
        return NSClassFromString("XCTestCase") != nil
        #else
        return false
        #endif
    }

    private func workoutDismissed() {
        // Only consider a newly completed phone workout, never an abandoned session.
        guard model.finishedWorkoutForReview else { return }
        model.finishedWorkoutForReview = false
        scheduleReview()
    }

    private func scheduleReview() {
        reviewTask?.cancel()
        reviewTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard scenePhase == .active, model.activeRuntime == nil, hasCompletedOnboarding, purchases.isUnlocked else { return }
            // Avoid interrupting any other modal that opened during the delay.
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
                  root.presentedViewController == nil else { return }
            let policy = ReviewPromptPolicy()
            guard policy.shouldRequest(afterOnboarding: false) else { return }
            policy.recordRequest()
            requestReview()
        }
    }
}
