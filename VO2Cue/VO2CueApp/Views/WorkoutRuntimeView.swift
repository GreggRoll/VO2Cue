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
                Button("End workout", role: .destructive) { runtime.end() }
                Button("Keep going", role: .cancel) { }
            } message: {
                Text("The elapsed portion will remain in your local history.")
            }
        }
        .alert("Workout audio", isPresented: Binding(
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
    @Bindable var runtime: WorkoutRuntime
    @Binding var confirmEnd: Bool

    var body: some View {
        VStack(spacing: 22) {
            WorkoutPhaseHeader(phase: runtime.snapshot.phase)
            Spacer(minLength: 0)
            WorkoutTimerReadout(snapshot: runtime.snapshot)
            Spacer(minLength: 0)
            NextPhaseView(nextPhase: runtime.nextPhase)
            WorkoutControls(runtime: runtime, confirmEnd: $confirmEnd)
        }
        .padding()
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

            ProgressView(value: snapshot.progress)
                .tint(.primary)
                .accessibilityLabel("Phase progress")
                .accessibilityValue(Text(snapshot.progress, format: .percent.precision(.fractionLength(0))))

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
    @Bindable var runtime: WorkoutRuntime
    @Binding var confirmEnd: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button("End", systemImage: "xmark") { confirmEnd = true }
                .buttonStyle(.bordered)
                .tint(.red)

            Button {
                runtime.status == .paused ? runtime.resume() : runtime.pause()
            } label: {
                Label(runtime.status == .paused ? "Resume" : "Pause", systemImage: runtime.status == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Skip", systemImage: "forward.end.fill") { model.skipPhase() }
                .buttonStyle(.bordered)
        }
        .controlSize(.large)
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
