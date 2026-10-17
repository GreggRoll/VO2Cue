import SwiftUI

struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutProfile
    @State private var cooldownEnabled: Bool

    init(profile: WorkoutProfile?) {
        let draft = profile ?? WorkoutProfile(
            name: "New workout",
            warmupSeconds: 10 * 60,
            workSeconds: 4 * 60,
            recoverySeconds: 3 * 60,
            repeatCount: 4,
            cooldownSeconds: 0,
            countdownSeconds: 3,
            hardCueLabel: "Hard",
            recoveryCueLabel: "Recover",
            cues: CueSettings()
        )
        _draft = State(initialValue: draft)
        _cooldownEnabled = State(initialValue: draft.cooldownSeconds > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $draft.name)
                    Picker("Activity", selection: $draft.activity) {
                        ForEach(WorkoutActivity.allCases) { activity in
                            Text(activity.title).tag(activity)
                        }
                    }
                }

                Section("Intervals") {
                    DurationStepper(label: "Warm up", seconds: $draft.warmupSeconds, range: 0...(60 * 60), step: 60)
                    DurationStepper(label: "Work interval", seconds: $draft.workSeconds, range: 15...(30 * 60), step: 15)
                    DurationStepper(label: "Recovery", seconds: $draft.recoverySeconds, range: 15...(30 * 60), step: 15)
                    Stepper("Rounds: \(draft.repeatCount)", value: $draft.repeatCount, in: 1...20)
                    Toggle("Cool down", isOn: $cooldownEnabled)
                    if cooldownEnabled {
                        DurationStepper(label: "Cool down duration", seconds: $draft.cooldownSeconds, range: 60...(60 * 60), step: 60)
                    }
                }

                Section {
                    TextField("Hard cue", text: $draft.hardCueLabel)
                    TextField("Recovery cue", text: $draft.recoveryCueLabel)
                } header: {
                    Text("Labels")
                } footer: {
                    Text("These labels appear on screen and are spoken when voice cues are on.")
                }

                Section("Eyes-free cues") {
                    Stepper("Countdown: \(draft.countdownSeconds) seconds", value: $draft.countdownSeconds, in: 0...10)
                    Toggle("Watch haptics", isOn: $draft.cues.hapticsEnabled)
                    Toggle("Tones", isOn: $draft.cues.tonesEnabled)
                    Toggle("Spoken cues", isOn: $draft.cues.voiceEnabled)
                    Toggle("Halfway cue", isOn: $draft.cues.halfwayCueEnabled)
                }
                ProfileHeartRateSection(profile: $draft, preferences: model.heartPreferences)
            }
            .navigationTitle("Workout profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !cooldownEnabled { draft.cooldownSeconds = 0 }
                        model.upsert(draft)
                        dismiss()
                    }
                    .disabled(draft.heartRateGuidance?.enabled == true &&
                        [draft.heartRateGuidance?.hardOverride, draft.heartRateGuidance?.recoveryOverride]
                            .compactMap { $0 }.contains { !$0.isValid })
                }
            }
            .onChange(of: cooldownEnabled) { _, enabled in
                if enabled, draft.cooldownSeconds == 0 { draft.cooldownSeconds = 5 * 60 }
            }
        }
    }
}

private struct DurationStepper: View {
    let label: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        Stepper(value: $seconds, in: range, step: step) {
            LabeledContent(label, value: seconds.timerText)
        }
        .accessibilityLabel(label)
        .accessibilityValue(seconds.timerText)
    }
}
