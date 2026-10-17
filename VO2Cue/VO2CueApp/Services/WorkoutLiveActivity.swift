import ActivityKit
import Foundation
import OSLog

@MainActor
final class WorkoutLiveActivity {
    private var activity: Activity<WorkoutActivityAttributes>?
    private var updates: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.gregadams.vo2cue", category: "LiveActivity")

    init() {
        // A previous process's timer no longer owns these activities.
        let previous = Activity<WorkoutActivityAttributes>.activities
        updates = Task {
            for activity in previous { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start(_ runtime: WorkoutRuntime) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: WorkoutActivityAttributes(workoutName: runtime.profile.name),
                content: content(runtime), pushType: nil
            )
        } catch { logger.error("Could not start workout Live Activity: \(error.localizedDescription)") }
    }

    func update(_ runtime: WorkoutRuntime) {
        guard let activity else { return }
        let content = content(runtime)
        let finished = content.state.isFinished
        if finished { self.activity = nil }
        let previous = updates
        updates = Task {
            await previous?.value
            if finished {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60)))
            } else {
                await activity.update(content)
            }
        }
    }

    private func content(_ runtime: WorkoutRuntime) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        let now = Date()
        let snapshot = runtime.snapshot
        let finished = runtime.status == .ended || runtime.status == .completed
        let remaining = Double(snapshot.phase.durationSeconds) - snapshot.phaseElapsedSeconds
        let state = WorkoutActivityAttributes.ContentState(
            phaseTitle: finished ? (runtime.status == .completed ? "Workout complete" : "Workout ended") : snapshot.phase.displayTitle,
            symbol: finished ? "checkmark.circle" : snapshot.phase.kind.systemImage,
            round: snapshot.phase.roundDescription,
            nextPhase: runtime.nextPhase?.displayTitle ?? "Finish",
            phaseStart: now.addingTimeInterval(-snapshot.phaseElapsedSeconds),
            phaseEnd: now.addingTimeInterval(max(0, remaining)),
            remainingSeconds: snapshot.remainingSeconds,
            isPaused: runtime.status == .paused,
            isFinished: finished
        )
        return ActivityContent(state: state, staleDate: state.isPaused || finished ? nil : state.phaseEnd)
    }
}
