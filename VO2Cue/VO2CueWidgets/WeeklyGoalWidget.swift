import SwiftUI
import WidgetKit

struct WeeklyGoalEntry: TimelineEntry {
    let date: Date
    let data: WeeklyGoalWidgetData
    let progress: WeeklyGoalWidgetProgress

    init(date: Date, data: WeeklyGoalWidgetData) {
        self.date = date
        self.data = data
        progress = data.progress(at: date)
    }

    static var preview: Self {
        let now = Date()
        let data = WeeklyGoalWidgetData(
            weeklyGoalMinutes: 60,
            sessions: [.init(id: UUID(), startedAt: now, activeSeconds: 2_520)],
            workout: .init(id: UUID(), name: "Norwegian 4×4")
        )
        return Self(date: now, data: data)
    }
}

struct WeeklyGoalProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalEntry) -> Void) {
        completion(context.isPreview ? .preview : WeeklyGoalEntry(date: .now, data: WeeklyGoalWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalEntry>) -> Void) {
        let now = Date()
        let data = WeeklyGoalWidgetStore.load()
        let nextWeek = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end
            ?? now.addingTimeInterval(24 * 60 * 60)
        // Include the reset in the timeline so last week's completion cannot linger.
        let entries = [WeeklyGoalEntry(date: now, data: data), WeeklyGoalEntry(date: nextWeek, data: data)]
        completion(Timeline(entries: entries, policy: .after(min(nextWeek, now.addingTimeInterval(60 * 60)))))
    }
}

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeeklyGoalWidgetStore.kind, provider: WeeklyGoalProvider()) { entry in
            WeeklyGoalWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(WorkoutWidgetRoute.progress.url)
        }
        .configurationDisplayName("Weekly goal")
        .description("See your active-minute goal progress. Start your most recent workout from the medium widget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeeklyGoalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeeklyGoalEntry

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 16) {
                GoalRing(progress: entry.progress)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    GoalSummary(progress: entry.progress)
                    Spacer(minLength: 0)
                    if let workout = entry.data.workout {
                        Text(workout.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Link(destination: WorkoutWidgetRoute.startWorkout(workout.id).url) {
                            Label("Start workout", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(.black)
                                .background(.orange.gradient, in: .capsule)
                        }
                        .accessibilityLabel("Start \(workout.name)")
                        .accessibilityHint("Opens VO2Cue and starts the workout")
                    } else {
                        Link("Choose a workout", destination: WorkoutWidgetRoute.workouts.url)
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("This week")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                GoalRing(progress: entry.progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(entry.progress.activeMinutes) / \(entry.progress.goalMinutes) min")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly goal")
            .accessibilityValue("\(entry.progress.activeMinutes) of \(entry.progress.goalMinutes) active minutes, \(entry.progress.percent) percent complete")
            .accessibilityHint("Opens your progress in VO2Cue")
        }
    }
}

private struct GoalRing: View {
    let progress: WeeklyGoalWidgetProgress

    var body: some View {
        ZStack {
            Circle().stroke(.orange.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(.orange.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if progress.isComplete {
                    Image(systemName: "checkmark")
                        .font(.title2.bold())
                        .foregroundStyle(.orange)
                    Text("Goal met").font(.caption2.bold())
                } else {
                    Text("\(progress.percent)%")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    Text("of goal").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(5)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly goal completion")
        .accessibilityValue("\(progress.percent) percent")
    }
}

private struct GoalSummary: View {
    let progress: WeeklyGoalWidgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(progress.isComplete ? "Weekly goal met" : "This week")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(progress.activeMinutes) / \(progress.goalMinutes) active min")
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .systemSmall) {
    WeeklyGoalWidget()
} timeline: {
    WeeklyGoalEntry.preview
}

#Preview(as: .systemMedium) {
    WeeklyGoalWidget()
} timeline: {
    WeeklyGoalEntry.preview
    WeeklyGoalEntry(date: .now, data: WeeklyGoalWidgetData(weeklyGoalMinutes: 30, sessions: WeeklyGoalEntry.preview.data.sessions, workout: WeeklyGoalEntry.preview.data.workout))
}
