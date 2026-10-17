import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReviewPromptPolicy.reviewedKey) private var hasAlreadyReviewed = false
    @State private var showingFeedback = false
    @State private var showingIntroduction = false
    @State private var healthAlertTitle = ""
    @State private var healthAlertMessage = ""
    @State private var healthAlertOffersSettings = false
    @State private var isShowingHealthAlert = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section("VO2Cue access") {
                    LabeledContent("Plan", value: purchases.access.title)
                    if purchases.access == .paidApp {
                        Text("You bought VO2Cue before it became free to download. Your lifetime access is included—no subscription needed.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if purchases.access == .monthly {
                        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    Button(purchases.isRestoring ? "Restoring…" : "Restore purchases") {
                        Task { await purchases.restore() }
                    }.disabled(purchases.isBusy)
                    if let message = purchases.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    Button("Review introduction") { showingIntroduction = true }
                }
                Section {
                    NavigationLink {
                        WorkoutRemindersView(store: model.reminders)
                    } label: {
                        LabeledContent("Workout reminders", value: model.reminders.schedule.enabled ? "On" : "Off")
                    }
                } header: {
                    Text("Training habit")
                }
                Section {
                    NavigationLink { HeartRateSettingsView() } label: { Label("Heart-rate targets", systemImage: "heart.fill") }
                    NavigationLink { HeartSyncTestingView() } label: { Label("Heart Sync Preview", systemImage: "applewatch") }
                } header: { Text("Heart rate · testing preview") }
                Section {
                    Toggle("Save completed workouts", isOn: $model.healthSavingEnabled)
                    LabeledContent("Permission", value: model.healthStore.authorizationState.title)
                    Button {
                        requestHealthAccess()
                    } label: {
                        HStack(spacing: 10) {
                            if model.healthStore.isRequestingAuthorization {
                                ProgressView()
                            }
                            Text(model.healthStore.isRequestingAuthorization ? "Requesting Health access…" : "Request Health access")
                        }
                    }
                    .disabled(model.healthStore.isRequestingAuthorization)
                    if let error = model.healthStore.lastErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Phone timers request workout permission. Live Watch workouts also request heart-rate access on Watch and are saved there. Without access, the phone timer and local history still work.")
                }

                Section("Privacy") {
                    Label("No account", systemImage: "person.crop.circle.badge.xmark")
                    Label("No ads or tracking", systemImage: "hand.raised")
                    Label("Workouts stay on your devices", systemImage: "externaldrive")
                    Text("Your profiles and VO2Cue history stay on your devices. Health data is managed by Apple Health according to your permissions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Text("VO2Cue is an eyes-free 4×4 interval coach for Apple Watch, swimming, running, cycling, rowing, and gym cardio.")
                }
                Section {
                    Text("I’m just one guy building VO2Cue, and your support means everything to me. A rating or review on the App Store helps others discover the app. Thank you!")
                    Link(destination: URL(string: "https://apps.apple.com/app/id6804899072?action=write-review")!) {
                        Label("Rate VO2Cue on the App Store", systemImage: "star")
                    }
                    Toggle("I’ve already reviewed VO2Cue", isOn: $hasAlreadyReviewed)
                } header: {
                    Text("Support VO2Cue")
                } footer: {
                    Text("Already left a review? Turn this on to stop future rating requests.")
                }

                Section {
                    Button {
                        showingFeedback = true
                    } label: {
                        Label("Send feedback", systemImage: "bubble.left.and.bubble.right")
                    }
                } footer: {
                    Text("Report an issue, request a feature, or just say hi. Positive feedback is very much appreciated!")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingFeedback) {
                FeedbackView()
            }
            .sheet(isPresented: $showingIntroduction) {
                WelcomeView { showingIntroduction = false }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.healthStore.refreshAuthorizationState()
                }
            }
            .alert(healthAlertTitle, isPresented: $isShowingHealthAlert) {
                if healthAlertOffersSettings {
                    Button("Open Settings") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settingsURL)
                        }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(healthAlertMessage)
            }
        }
    }

    private func requestHealthAccess() {
        Task {
            let allowed = await model.healthStore.requestAuthorization()
            healthAlertOffersSettings = false

            if let error = model.healthStore.lastErrorMessage {
                healthAlertTitle = "Couldn’t Request Health Access"
                healthAlertMessage = error
            } else if allowed {
                healthAlertTitle = "Health Access Ready"
                healthAlertMessage = "Completed workouts can now be saved to Apple Health."
            } else {
                switch model.healthStore.authorizationState {
                case .denied:
                    healthAlertTitle = "Health Access Is Off"
                    healthAlertMessage = "Allow VO2Cue to write workouts in Settings to save completed sessions to Apple Health."
                    healthAlertOffersSettings = true
                case .unavailable:
                    healthAlertTitle = "Apple Health Unavailable"
                    healthAlertMessage = "Apple Health isn’t available on this device."
                case .notDetermined, .available:
                    healthAlertTitle = "Health Access Not Changed"
                    healthAlertMessage = "No Health permissions were changed. You can try again or review VO2Cue in Settings."
                    healthAlertOffersSettings = true
                }
            }

            isShowingHealthAlert = true
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
