import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VO2CueWidgets: WidgetBundle {
    var body: some Widget {
        WeeklyGoalWidget()
        VO2CueLiveActivity()
    }
}

struct VO2CueLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.attributes.workoutName, systemImage: "waveform.path.ecg")
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    if context.state.isPaused { Text("Paused").font(.caption.bold()) }
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(context.state.phaseTitle, systemImage: context.state.symbol)
                            .font(.headline)
                        if let round = context.state.round { Text(round).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if !context.state.isFinished {
                        PhaseCountdown(state: context.state)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .frame(maxWidth: 140, alignment: .trailing)
                    }
                }
                if !context.state.isFinished {
                    if context.isStale && !context.state.isPaused {
                        Text("Open VO2Cue for the current phase").font(.caption)
                    } else {
                        Text("Next: \(context.state.nextPhase)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.9))
            .activitySystemActionForegroundColor(.orange)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phaseTitle, systemImage: context.state.symbol).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseCountdown(state: context.state).monospacedDigit().frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.isPaused ? "Paused" : context.state.round ?? context.attributes.workoutName)
                        Spacer()
                        if !context.state.isFinished { Text("Next: \(context.state.nextPhase)") }
                    }.font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.state.symbol).foregroundStyle(.orange)
            } compactTrailing: {
                PhaseCountdown(state: context.state).frame(width: 55)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.state.symbol).foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}

private struct PhaseCountdown: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isFinished {
                Image(systemName: "checkmark")
            } else if state.isPaused {
                Text(String(format: "%d:%02d", state.remainingSeconds / 60, state.remainingSeconds % 60))
            } else {
                Text(timerInterval: state.phaseStart...max(state.phaseStart, state.phaseEnd), countsDown: true)
            }
        }
        .monospacedDigit()
        .contentTransition(.numericText(countsDown: true))
        .accessibilityLabel(state.isFinished ? "Finished" : "Phase time remaining")
    }
}
