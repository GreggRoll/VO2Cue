import SwiftUI

private enum ProfileSheet: Identifiable {
    case create
    case edit(WorkoutProfile)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let profile): "edit-\(profile.id.uuidString)"
        }
    }
}

struct WorkoutsView: View {
    @Environment(AppModel.self) private var model
    @State private var presentedSheet: ProfileSheet?
    @State private var showingLibrary = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.workoutsNavigationPath) {
            List {
                Section { WeeklyGoalView() }
                Section {
                    Button("Browse workout library", systemImage: "books.vertical") { showingLibrary = true }
                }
                Section {
                    ForEach(model.profiles) { profile in
                        NavigationLink(value: profile.id) {
                            ProfileRow(profile: profile)
                        }
                        .accessibilityIdentifier("workoutProfile_\(profile.id.uuidString)")
                        .swipeActions(edge: .leading) {
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                model.duplicate(profile)
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { model.profiles[$0].id })
                        model.deleteProfiles(ids: ids)
                    }
                } header: {
                    Text("Your workouts")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profiles sync to Apple Watch when it is connected.")
                        Text(model.watchSyncStatus.title)
                    }
                }
            }
            .navigationTitle("VO2Cue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Workout", systemImage: "plus") {
                        presentedSheet = .create
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let profile = model.profile(id: id) {
                    ProfileDetailView(profile: profile) {
                        presentedSheet = .edit(profile)
                    }
                } else {
                    ContentUnavailableView("Workout unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .create:
                    ProfileEditorView(profile: nil)
                        .environment(model)
                case .edit(let profile):
                    ProfileEditorView(profile: profile)
                        .environment(model)
                }
            }
            .sheet(isPresented: $showingLibrary) { WorkoutLibraryView() }
        }
    }
}

private struct ProfileRow: View {
    let profile: WorkoutProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(profile.name)
                .font(.headline)
            HStack(spacing: 12) {
                Label(profile.activity.title, systemImage: "figure.run")
                Label(profile.estimatedDuration.timerText, systemImage: "clock")
                Label("\(profile.repeatCount) rounds", systemImage: "repeat")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileDetailView: View {
    @Environment(AppModel.self) private var model
    let profile: WorkoutProfile
    let edit: () -> Void

    private let phaseColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkoutHero(profile: profile)
                PhaseGrid(profile: profile, columns: phaseColumns)
                CueSummary(profile: profile)
                Button {
                    model.start(profile)
                } label: {
                    Label(model.isPreparingWorkout ? "Preparing audio…" : "Start workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isPreparingWorkout)
                .accessibilityHint("Prepares cues and starts the workout timer")
                .alert("Workout audio", isPresented: Binding(
                    get: { model.workoutErrorMessage != nil && model.activeRuntime == nil },
                    set: { if !$0 { model.workoutErrorMessage = nil } }
                )) {
                    Button("OK") { model.workoutErrorMessage = nil }
                } message: { Text(model.workoutErrorMessage ?? "") }
            }
            .padding()
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: edit)
            }
        }
    }
}

private struct WorkoutHero: View {
    let profile: WorkoutProfile

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(profile.estimatedDuration.timerText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text("estimated duration")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimated duration \(profile.estimatedDuration.timerText)")
    }
}

private struct PhaseGrid: View {
    let profile: WorkoutProfile
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            PhaseTile(title: "Warm up", value: profile.warmupSeconds.timerText, icon: "flame")
            PhaseTile(title: profile.hardCueLabel, value: profile.workSeconds.timerText, icon: "bolt.fill")
            PhaseTile(title: profile.recoveryCueLabel, value: profile.recoverySeconds.timerText, icon: "arrow.down.heart")
            PhaseTile(title: "Rounds", value: "\(profile.repeatCount)", icon: "repeat")
            if profile.cooldownSeconds > 0 {
                PhaseTile(title: "Cool down", value: profile.cooldownSeconds.timerText, icon: "wind")
            }
        }
    }
}

private struct PhaseTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct CueSummary: View {
    let profile: WorkoutProfile

    private var enabledCues: [String] {
        var result: [String] = []
        if profile.cues.hapticsEnabled { result.append("haptics") }
        if profile.cues.tonesEnabled { result.append("tones") }
        if profile.cues.voiceEnabled { result.append("voice") }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eyes-free cues")
                .font(.headline)
            Text(enabledCues.isEmpty ? "Visual only" : enabledCues.formatted())
                .foregroundStyle(.secondary)
            Text("Countdown: \(profile.countdownSeconds) seconds")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
