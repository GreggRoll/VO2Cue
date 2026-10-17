import SwiftUI

struct HeartRateSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var maximum = ""
    @State private var source = MaximumHeartRateSource.entered
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Maximum heart rate (BPM)", text: $maximum)
                    .keyboardType(.numberPad).accessibilityIdentifier("maximumHeartRate")
                Picker("Source", selection: $source) {
                    ForEach(MaximumHeartRateSource.allCases) { Text($0.title).tag($0) }
                }
                Button("Save maximum") {
                    model.heartPreferences = HeartRatePreferences(maximumBPM: Int(maximum), source: source)
                    saved = true
                }.disabled(Int(maximum).map { !(100...230).contains($0) } ?? true)
                if saved { Label("Maximum saved", systemImage: "checkmark").foregroundStyle(.green) }
                if let current = model.heartPreferences.confirmedMaximum {
                    LabeledContent("Confirmed maximum", value: "\(current) BPM · \(model.heartPreferences.source.title)")
                    Button("Clear maximum", role: .destructive) {
                        model.heartPreferences.maximumBPM = nil
                        maximum = ""
                        saved = false
                    }
                }
            } header: { Text("Your maximum heart rate") }
            footer: {
                Text("Enter and confirm your own measured, entered, or estimated maximum (100–230 BPM). VO2Cue never treats your highest Apple Health reading as your maximum. You can use custom profile ranges instead.")
            }
            Section {
                Text("Hard intervals: 85–95% of maximum. Active recovery: 60–70%. These editable training targets follow NTNU CERG’s 4×4 guidance.")
                Link("Read NTNU’s exercise advice", destination: URL(string: "https://www.ntnu.edu/cerg/advice")!)
                Text("Enable heart-rate guidance in a workout profile. Targets change with each hard and recovery interval. Warmup and cooldown show BPM without deviation cues.")
                Text("Changes apply to the next workout. Your maximum stays on your devices and syncs directly to Apple Watch.")
            } header: { Text("Phase targets") }
            Section {
                NavigationLink("Heart Sync Preview testing") { HeartSyncTestingView() }
            }
        }
        .navigationTitle("Heart-rate targets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            maximum = model.heartPreferences.confirmedMaximum.map(String.init) ?? ""
            source = model.heartPreferences.source
        }
        .onChange(of: maximum) { _, _ in saved = false }
        .onChange(of: source) { _, _ in saved = false }
    }
}

struct ProfileHeartRateSection: View {
    @Binding var profile: WorkoutProfile
    let preferences: HeartRatePreferences

    private var guidance: HeartRateGuidance { profile.heartRateGuidance ?? .init() }
    private func field<Value>(_ keyPath: WritableKeyPath<HeartRateGuidance, Value>) -> Binding<Value> {
        Binding(get: { guidance[keyPath: keyPath] }, set: { value in
            var updated = guidance
            updated[keyPath: keyPath] = value
            profile.heartRateGuidance = updated
        })
    }

    var body: some View {
        Section {
            Toggle("Heart-rate guidance", isOn: Binding(
                get: { profile.heartRateGuidance?.enabled == true },
                set: { value in var updated = guidance; updated.enabled = value; profile.heartRateGuidance = updated }
            )).accessibilityIdentifier("heartRateGuidanceToggle")
            if profile.heartRateGuidance?.enabled == true {
                Toggle("Heart-rate cues", isOn: field(\.cuesEnabled))
                rangeEditor("Hard", phase: .work, keyPath: \.hardOverride)
                rangeEditor("Recovery", phase: .recovery, keyPath: \.recoveryOverride)
                NavigationLink("Personal maximum heart rate") { HeartRateSettingsView() }
            }
        } header: { Text("Heart-rate targets") }
        footer: {
            Text("Optional Apple Watch guidance. Hard and recovery targets change with the interval. Fresh readings are required; timing still works without a signal. Heart-rate voice cues follow Spoken cues above.")
        }
    }

    @ViewBuilder private func rangeEditor(_ title: String, phase: WorkoutPhaseKind,
                                          keyPath: WritableKeyPath<HeartRateGuidance, HeartRateRange?>) -> some View {
        let resolved = profile.resolvingHeartRate(preferences).heartRateGuidance?.target(for: phase)
        Toggle("Custom \(title.lowercased()) range", isOn: Binding(get: { guidance[keyPath: keyPath] != nil }, set: { enabled in
            var updated = guidance
            updated[keyPath: keyPath] = enabled ? (resolved ?? HeartRateRange(lower: 0, upper: 0)) : nil
            profile.heartRateGuidance = updated
        }))
        if guidance[keyPath: keyPath] != nil {
            HStack {
                Text(title).frame(minWidth: 65, alignment: .leading)
                TextField("Lower BPM", value: Binding(get: { guidance[keyPath: keyPath]?.lower ?? 0 }, set: { value in
                    var updated = guidance; updated[keyPath: keyPath]?.lower = value; profile.heartRateGuidance = updated
                }), format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                Text("–")
                TextField("Upper BPM", value: Binding(get: { guidance[keyPath: keyPath]?.upper ?? 0 }, set: { value in
                    var updated = guidance; updated[keyPath: keyPath]?.upper = value; profile.heartRateGuidance = updated
                }), format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            if guidance[keyPath: keyPath]?.isValid != true {
                Text("Enter a lower and upper value from 30–250 BPM; upper must be greater.").font(.caption).foregroundStyle(.orange)
            }
        } else {
            LabeledContent(title, value: resolved.map { "\($0.label) BPM" } ?? "Set a maximum or custom range")
                .font(.subheadline)
        }
    }
}

struct HeartSyncTestingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section("Heart Sync Preview") {
                Text("This build is for testing phase-aware heart rate and phone–Watch workout mirroring.")
                Text("Install this build on both iPhone and Apple Watch. Enable Live Activities for VO2Cue for locked-phone testing. Grant workout and heart-rate access on Watch when asked.")
            }
            Section("Try a workout") {
                Button("Add 6½-minute Heart Sync Check", systemImage: "plus.circle") {
                    let profile = WorkoutProfile.heartSyncCheck
                    model.upsert(profile)
                    model.selectedTab = .workouts
                    model.workoutsNavigationPath = [profile.id]
                }
                Text("1. Set your maximum or custom BPM ranges, then enable Heart-rate guidance in a workout profile.")
                Text("2. Tap Start with Apple Watch on iPhone, or start that profile on Watch. Compare phase, round, timer, BPM and target.")
                Text("3. Pause, resume, skip and end from each device. Phone controls wait for Watch confirmation.")
                Text("4. Lock the phone, lower your wrist, move out of range and return. Watch should keep running. A stale reading must disappear after 15 seconds.")
                Text("5. Test a full hard/recovery transition and check Building/Settling. Finish and confirm there is only one Apple Health workout and one history entry.")
                Text("No simulated heart rate is used in TestFlight. Physical-device testing is needed to evaluate sensor and connection delays, including swimming gaps.")
            }
            Section("Live diagnostics") {
                HeartSyncDiagnostics(feed: model.workoutMirror.heartRate)
            }
        }.navigationTitle("Heart Sync Preview").navigationBarTitleDisplayMode(.inline)
    }
}

struct HeartSyncDiagnostics: View {
    let feed: HeartRateFeed
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(feed.connectionMessage)
                if let sample = feed.presentation.sample {
                    LabeledContent("Reading age", value: "\(max(0, Int(context.date.timeIntervalSince(sample.date))))s")
                }
                if let received = feed.receivedAt {
                    LabeledContent("Last workout update", value: "\(max(0, Int(context.date.timeIntervalSince(received))))s ago")
                }
                if let delay = feed.deliveryMilliseconds {
                    LabeledContent("Estimated delivery", value: "\(delay) ms")
                    Text("Uses device clocks; not a sensor-latency measurement.").font(.caption).foregroundStyle(.secondary)
                }
            }.font(.subheadline)
        }
    }
}
