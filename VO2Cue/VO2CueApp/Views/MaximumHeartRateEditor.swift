import SwiftUI

struct MaximumHeartRateEditor: View {
    @Binding var maximum: String
    @Binding var source: MaximumHeartRateSource
    @State private var age = ""
    @FocusState private var focusedField: Field?
    private enum Field { case maximum, age }

    private var estimate: Int? { Int(age).flatMap(HeartRatePreferences.estimatedMaximum) }

    var body: some View {
        Section {
            HStack {
                TextField("Maximum heart rate (BPM)", text: $maximum)
                    .keyboardType(.numberPad).accessibilityIdentifier("maximumHeartRate")
                    .focused($focusedField, equals: .maximum)
                if focusedField == .maximum { doneButton }
            }
            Picker("Source", selection: $source) {
                ForEach(MaximumHeartRateSource.allCases) { Text($0.title).tag($0) }
            }
        } header: { Text("Your maximum heart rate") }
        footer: { Text("Enter a measured or known maximum, or use the age estimate below. You can edit it later in Settings.") }
        Section {
            HStack {
                TextField("Age in years", text: $age)
                    .keyboardType(.numberPad).accessibilityIdentifier("heartRateAge")
                    .focused($focusedField, equals: .age)
                if focusedField == .age { doneButton }
            }
            if let estimate { LabeledContent("Estimated maximum", value: "\(estimate) BPM") }
            Button("Use age estimate") {
                guard let estimate else { return }
                focusedField = nil
                maximum = String(estimate)
                source = .estimated
            }.disabled(estimate == nil).accessibilityIdentifier("useHeartRateEstimate")
        } header: { Text("Calculate from age") }
        footer: { Text("220 − (0.7 × age), rounded to the nearest BPM. Ages 13–100. This is an estimate, not a measurement. Your age is used for this calculation only and is not saved.") }
    }
    private var doneButton: some View {
        Button("Done") { focusedField = nil }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("heartRateKeyboardDone")
    }

}

struct HeartRateOnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var maximum = ""
    @State private var source = MaximumHeartRateSource.entered
    var isIntroduction = false
    let onComplete: () -> Void

    private var valid: Bool { Int(maximum).map { (100...230).contains($0) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if isIntroduction { Text("5 / 5").font(.caption).foregroundStyle(.secondary) }
                    Text("Train in your range").font(.largeTitle.bold())
                        .accessibilityIdentifier("heartRateOnboardingTitle")
                    Text("Personalize the range slider and spoken heart-rate guidance on iPhone and Apple Watch. Your target changes between hard and recovery intervals.")
                }
                MaximumHeartRateEditor(maximum: $maximum, source: $source)
                Section {
                    if let max = Int(maximum), (100...230).contains(max) {
                        let guidance = HeartRateGuidance(maximumBPM: max)
                        LabeledContent("Hard · 85–95%", value: "\(guidance.target(for: .work)!.label) BPM")
                        LabeledContent("Recovery · 60–70%", value: "\(guidance.target(for: .recovery)!.label) BPM")
                    }
                    Text("These are editable training targets. During warmup and cooldown, the Watch shows your heart rate without a target. Changes apply to your next workout.")
                } header: { Text("Your phase targets") }
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 12) {
                Button("Save and continue") {
                    guard valid else { return }
                    model.heartPreferences = .init(maximumBPM: Int(maximum), source: source)
                    complete()
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!valid).accessibilityIdentifier("saveHeartRateOnboarding")
                Button("Set up later") { complete() }
                    .font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("skipHeartRateOnboarding")
            }.padding().frame(maxWidth: .infinity).background(.bar)
        }
        .onAppear {
            maximum = model.heartPreferences.confirmedMaximum.map(String.init) ?? ""
            source = model.heartPreferences.source
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "hasOfferedHeartRateSetup")
        onComplete()
    }
}
