import SwiftUI
import UIKit

struct WorkoutRuntimeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var runtime: WorkoutRuntime
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if runtime.status == .completed || runtime.status == .ended {
                    WorkoutCompletionView(runtime: runtime) {
                        model.dismissRuntime()
                    }
                } else {
                    ActiveWorkoutView(runtime: runtime, confirmEnd: $confirmEnd)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("End this workout?", isPresented: $confirmEnd) {
                Button("End workout", role: .destructive) { model.controlWorkout(.end) }
                Button("Keep going", role: .cancel) { }
            } message: {
                Text("The elapsed portion will remain in your local history.")
            }
        }
        .alert("Workout", isPresented: Binding(
            get: { model.workoutErrorMessage != nil },
            set: { if !$0 { model.workoutErrorMessage = nil } }
        )) {
            Button("OK") { model.workoutErrorMessage = nil }
        } message: { Text(model.workoutErrorMessage ?? "") }
        .interactiveDismissDisabled(runtime.status == .running || runtime.status == .paused)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .animation(reduceMotion ? nil : .smooth, value: runtime.status)
    }
}

private struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var runtime: WorkoutRuntime
    @Binding var confirmEnd: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WorkoutPhaseHeader(phase: runtime.snapshot.phase)
                WorkoutTimerReadout(snapshot: runtime.snapshot)
                if !runtime.isMirrored {
                    ProgressView(value: runtime.snapshot.progress)
                        .tint(.primary).accessibilityLabel("Phase progress")
                }
                if runtime.isMirrored || runtime.profile.heartRateGuidance?.enabled == true {
                    HeartRateCard(feed: model.workoutMirror.heartRate, runtime: runtime)
                }
                RuntimeIntervalGraph(runtime: runtime)
                if runtime.isMirrored {
                    MirrorControlStatus(feed: model.workoutMirror.heartRate)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    NextPhaseView(nextPhase: runtime.nextPhase)
                }
            }.padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                if !dynamicTypeSize.isAccessibilitySize {
                    NextPhaseView(nextPhase: runtime.nextPhase)
                }
                WorkoutControls(runtime: runtime, confirmEnd: $confirmEnd)
            }.padding().background(.bar)
        }
        .background(phaseBackground.ignoresSafeArea())
    }

    private var phaseBackground: Color {
        switch runtime.snapshot.phase.kind {
        case .warmup: .orange.opacity(0.13)
        case .work: .red.opacity(0.16)
        case .recovery: .blue.opacity(0.15)
        case .cooldown: .mint.opacity(0.15)
        }
    }
}

private struct WorkoutPhaseHeader: View {
    let phase: WorkoutPhase

    var body: some View {
        VStack(spacing: 6) {
            Label(phase.displayTitle, systemImage: phase.kind.systemImage)
                .font(.title2.bold())
            if let round = phase.roundDescription {
                Text(round)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutTimerReadout: View {
    let snapshot: WorkoutSnapshot

    var body: some View {
        VStack(spacing: 20) {
            Text(snapshot.remainingSeconds.timerText)
                .font(.system(size: 84, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Time remaining")
                .accessibilityValue(snapshot.remainingSeconds.timerText)

            Text("Total remaining \(snapshot.totalRemainingSeconds.timerText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct NextPhaseView: View {
    let nextPhase: WorkoutPhase?

    var body: some View {
        HStack {
            Text("Next")
                .foregroundStyle(.secondary)
            Spacer()
            if let nextPhase {
                Label(nextPhase.displayTitle, systemImage: nextPhase.kind.systemImage)
            } else {
                Label("Finish", systemImage: "checkmark.circle")
            }
        }
        .font(.headline)
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var runtime: WorkoutRuntime
    @Binding var confirmEnd: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button("End", systemImage: "xmark") { confirmEnd = true }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("End")

            Button {
                model.controlWorkout(runtime.status == .paused ? .resume : .pause)
            } label: {
                Label(runtime.status == .paused ? "Resume" : "Pause", systemImage: runtime.status == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(runtime.status == .paused ? "Resume" : "Pause")

            Button("Skip", systemImage: "forward.end.fill") { model.skipPhase() }
                .buttonStyle(.bordered)
                .accessibilityLabel("Skip")
        }
        .controlSize(.large)
        .labelStyle(WorkoutControlLabelStyle(compact: dynamicTypeSize.isAccessibilitySize))
        .disabled(runtime.isMirrored && (!model.workoutMirror.heartRate.isConnected || model.workoutMirror.heartRate.pendingCommand))
    }
}

private struct WorkoutControlLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
        } else {
            HStack { configuration.icon; configuration.title }
        }
    }
}

private struct MirrorControlStatus: View {
    let feed: HeartRateFeed
    var body: some View {
        VStack(spacing: 6) {
            if feed.pendingCommand {
                ProgressView("Waiting for Watch confirmation…").font(.caption)
            }
            if let message = feed.lastCommandMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink("Sync diagnostics") { HeartSyncDiagnostics(feed: feed).padding() }
                .font(.caption)
        }
    }
}

private struct WorkoutCompletionView: View {
    let runtime: WorkoutRuntime
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: runtime.status == .completed ? "checkmark.circle.fill" : "stop.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(runtime.status == .completed ? .green : .orange)
                    .accessibilityHidden(true)
                Text(runtime.status == .completed ? "Workout complete" : "Workout ended")
                    .font(.largeTitle.bold())
                Text(runtime.actualActiveSeconds.timerText)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("completedActualDuration")
                Text(runtime.profile.name).foregroundStyle(.secondary)
                if let record = runtime.finishedRecord() {
                    RuntimeIntervalGraph(runtime: runtime)
                    WorkoutSummaryDetails(record: record)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WorkoutReflectionView(recordID: record.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .accessibilityElement(children: .contain)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: done) {
                Text("Done").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }
}
