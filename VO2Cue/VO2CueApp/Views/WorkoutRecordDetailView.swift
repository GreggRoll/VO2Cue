import SwiftUI

struct WorkoutRecordDetailView: View {
    let record: WorkoutRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(record.startedAt, format: .dateTime.month().day().year().hour().minute())
                    .foregroundStyle(.secondary)
                if let phases = record.phaseResults {
                    WorkoutIntervalGraph(phases: WorkoutGraphPhase.make(results: phases, guidance: record.heartRateGuidance),
                        trace: record.heartRateTrace ?? .init(), elapsed: Double(record.displayedSeconds), isLive: false)
                }
                WorkoutSummaryDetails(record: record)
                WorkoutReflectionView(recordID: record.id)
            }
            .padding()
        }
        .navigationTitle(record.profileName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutSummaryDetails: View {
    let record: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(record.completed ? "Completed" : "Ended early",
                  systemImage: record.completed ? "checkmark.circle" : "stop.circle")
                .font(.headline)
            LabeledContent(record.durationLabel, value: record.displayedSeconds.timerText)
                .font(.title3.bold()).monospacedDigit()
            if let phases = record.phaseResults {
                ForEach([WorkoutPhaseKind.warmup, .work, .recovery, .cooldown], id: \.self) { kind in
                    let seconds = phases.filter { $0.kind == kind }.reduce(0) { $0 + $1.activeSeconds }
                    LabeledContent(kind.summaryTitle, value: Int(seconds.rounded(.down)).timerText)
                        .monospacedDigit()
                }
                LabeledContent("Skipped phases", value: "\(record.skippedPhaseCount)")
                Text("Skipped time and pauses are excluded from active time.")
                    .font(.footnote).foregroundStyle(.secondary)
                Divider()
                Text("Phase breakdown").font(.headline)
                ForEach(phases) { phase in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent {
                            Text(Int(phase.activeSeconds.rounded(.down)).timerText).monospacedDigit()
                        } label: {
                            Text(phase.round.map { "\(phase.label) · round \($0)" } ?? phase.label)
                        }
                        if phase.skipped {
                            Text("Skipped remainder").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } else if record.actualActiveSeconds == nil {
                Text("This older entry stores recorded time, which may include skipped intervals. It is preserved in history but excluded from goals and charts.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Phase breakdown is unavailable for this session.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutReflectionView: View {
    @Environment(AppModel.self) private var model
    let recordID: UUID
    @State private var showingEditor = false

    var body: some View {
        let annotation = model.trainingProgress.annotation(for: recordID)
        VStack(alignment: .leading, spacing: 12) {
            Text("How did it feel?").font(.headline)
            if let effort = annotation.effort {
                LabeledContent("Effort", value: "\(effort) of 10")
            }
            if !annotation.note.isEmpty { Text(annotation.note) }
            Button(annotation.effort == nil && annotation.note.isEmpty ? "Add effort or note" : "Edit effort and note") {
                showingEditor = true
            }
            .accessibilityIdentifier("editWorkoutReflection")
            Text("Optional, private, and editable later in Progress.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingEditor) {
            WorkoutReflectionEditor(recordID: recordID, store: model.trainingProgress)
        }
    }
}

private struct WorkoutReflectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    let store: TrainingProgressStore
    @State private var effort: Int
    @State private var note: String

    init(recordID: UUID, store: TrainingProgressStore) {
        self.recordID = recordID
        self.store = store
        let annotation = store.annotation(for: recordID)
        // Drafts are intentionally seeded once; Save commits and Cancel discards.
        _effort = State(initialValue: annotation.effort ?? 0)
        _note = State(initialValue: annotation.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Effort", selection: $effort) {
                        Text("Not rated").tag(0)
                        ForEach(1...10, id: \.self) { rating in Text("\(rating) of 10").tag(rating) }
                    }
                    .accessibilityIdentifier("workoutEffort")
                } footer: {
                    Text("Your impression of the whole session: 1 is very easy, 10 is your hardest effort. This does not change your workout or estimate fitness.")
                }
                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("workoutNote")
                        .onChange(of: note) { _, value in
                            if value.count > 2_000 { note = String(value.prefix(2_000)) }
                        }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Workout reflection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setAnnotation(WorkoutAnnotation(effort: effort == 0 ? nil : effort, note: note), for: recordID)
                        if store.errorMessage == nil { dismiss() }
                    }
                }
            }
        }
    }
}

private extension WorkoutPhaseKind {
    var summaryTitle: String {
        switch self {
        case .warmup: "Warmup"
        case .work: "Work / steady"
        case .recovery: "Recovery"
        case .cooldown: "Cooldown"
        }
    }
}
