import SwiftUI

struct WeeklyGoalView: View {
    @Environment(AppModel.self) private var model
    @State private var editingGoal = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let week = TrainingProgress.weeks(records: model.history, now: context.date).last
            let seconds = week?.activeSeconds ?? 0
            let goal = model.trainingProgress.weeklyGoalMinutes
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("This week", systemImage: "target").font(.headline)
                    Spacer()
                    Button("Edit goal") { editingGoal = true }
                        .font(.subheadline)
                        .accessibilityIdentifier("editWeeklyGoal")
                }
                Text("\(seconds / 60) of \(goal) active minutes")
                    .font(.title3.bold()).monospacedDigit()
                    .accessibilityIdentifier("weeklyGoalSummary")
                ProgressView(value: min(Double(seconds) / Double(goal * 60), 1))
                    .accessibilityLabel("Weekly active-minute goal")
                    .accessibilityValue("\(seconds / 60) of \(goal) minutes")
                Text(seconds >= goal * 60 ? "You reached your personal goal. Every effort counts." : "Partial sessions count too. Choose an effort that fits your day.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $editingGoal) {
            WeeklyGoalEditor(store: model.trainingProgress)
        }
    }
}

private struct WeeklyGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: TrainingProgressStore
    @State private var minutes: Int

    init(store: TrainingProgressStore) {
        self.store = store
        // An intentional editing draft; Cancel leaves the saved goal untouched.
        _minutes = State(initialValue: store.weeklyGoalMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(minutes) minutes per week", value: $minutes, in: 1...10_080, step: 5)
                        .accessibilityIdentifier("weeklyGoalMinutes")
                } footer: {
                    Text("This is your personal target, not a health recommendation. Actual training time counts, including sessions ended early. Pauses and skipped time do not.")
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Weekly goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setGoal(minutes)
                        if store.errorMessage == nil { dismiss() }
                    }
                }
            }
        }
    }
}
