import SwiftUI
import Charts

struct TrainingProgressView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section { WeeklyGoalView() }
                Section("All sessions") {
                    LabeledContent("Completed sessions", value: "\(model.completedSessions)")
                    LabeledContent("Actual active minutes", value: "\(model.totalActiveSeconds / 60)")
                }
                Section("Last eight weeks") {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        WeeklyMinutesChart(weeks: TrainingProgress.weeks(records: model.history, now: context.date))
                    }
                    Text("Actual minutes from VO2Cue sessions, including sessions ended early. Sessions are counted in the week they started. Older recorded-time entries are excluded.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recent workouts") {
                    if model.history.isEmpty {
                        ContentUnavailableView("No workouts yet", systemImage: "figure.run.circle",
                                               description: Text("Your sessions and progress will appear here."))
                    } else {
                        ForEach(model.history) { record in
                            NavigationLink(value: record.id) { HistoryRow(record: record) }
                        }
                        .onDelete(perform: model.deleteHistory)
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: UUID.self) { id in
                if let record = model.history.first(where: { $0.id == id }) {
                    WorkoutRecordDetailView(record: record)
                } else {
                    ContentUnavailableView("Workout unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .toolbar {
                if !model.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
                Button("Clear history", role: .destructive) { model.clearHistory() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes local VO2Cue history and workout notes, and resets minute totals. Workouts already saved in Apple Health are not removed.")
            }
        }
    }
}

private struct WeeklyMinutesChart: View {
    let weeks: [TrainingWeek]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(weeks) { week in
                BarMark(x: .value("Week starting", week.start, unit: .day),
                        y: .value("Active minutes", week.minutes))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Week of \(week.start.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityValue("\(week.minutes.formatted(.number.precision(.fractionLength(0...1)))) active minutes")
            }
            .chartYScale(domain: 0...max(1, (weeks.map(\.minutes).max() ?? 0).rounded(.up)))
            .chartXAxis {
                AxisMarks(values: weeks.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.start }) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxisLabel("Active minutes")
            .frame(height: 220)
            .accessibilityLabel("Active minutes over the last eight weeks")
            if weeks.allSatisfy({ $0.activeSeconds == 0 }) {
                Text("Start a session to begin your progress chart.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.completed ? "checkmark.circle.fill" : "stop.circle")
                .foregroundStyle(record.completed ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.profileName).font(.headline)
                Text(record.startedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(record.durationLabel): \(record.displayedSeconds.timerText)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.profileName), \(record.completed ? "completed" : "ended early"), \(record.durationLabel) \(record.displayedSeconds.timerText), \(record.startedAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
