import SwiftUI

struct WatchRuntimeView: View {
    @Environment(WatchAppModel.self) private var model
    @Bindable var runtime: WorkoutRuntime
    @State private var confirmEnd = false

    var body: some View {
        Group {
            if runtime.status == .completed || runtime.status == .ended {
                completion
            } else {
                TabView {
                    timerPage
                    controlsPage
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd) {
            Button("End workout", role: .destructive) { model.control(.end) }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var timerPage: some View {
        ScrollView {
        VStack(spacing: 5) {
            Label(runtime.snapshot.phase.displayTitle, systemImage: runtime.snapshot.phase.kind.systemImage)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let round = runtime.snapshot.phase.roundDescription {
                Text(round)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(runtime.snapshot.remainingSeconds.timerText)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Time remaining")
                .accessibilityValue(runtime.snapshot.remainingSeconds.timerText)
            ProgressView(value: runtime.snapshot.progress)
                .tint(.primary)
            WatchHeartRateReadout(feed: model.heartRate, runtime: runtime)
        }
        }
        .padding(.horizontal, 4)
        .containerBackground(phaseColor.gradient, for: .tabView)
    }

    private var controlsPage: some View {
        VStack(spacing: 9) {
            Button {
                model.control(runtime.status == .paused ? .resume : .pause)
            } label: {
                Label(runtime.status == .paused ? "Resume" : "Pause", systemImage: runtime.status == .paused ? "play.fill" : "pause.fill")
            }
            .tint(.orange)

            Button("Skip", systemImage: "forward.end.fill") { model.control(.skip) }
                .tint(.blue)
            Button("End", systemImage: "xmark") { confirmEnd = true }
                .tint(.red)
        }
        .buttonStyle(.bordered)
    }

    private var completion: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: runtime.status == .completed ? "checkmark.circle.fill" : "stop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(runtime.status == .completed ? .green : .orange)
                    .accessibilityHidden(true)
                Text(runtime.status == .completed ? "Complete" : "Ended")
                    .font(.headline)
                Text(runtime.actualActiveSeconds.timerText)
                    .font(.title2.bold().monospacedDigit())
                Text("Active time").font(.caption2)
                ForEach([WorkoutPhaseKind.warmup, .work, .recovery, .cooldown], id: \.self) { kind in
                    let phases = runtime.phaseResults.filter { $0.kind == kind }
                    if !phases.isEmpty {
                        LabeledContent(kind.watchSummaryTitle,
                                       value: Int(phases.reduce(0) { $0 + $1.activeSeconds }.rounded(.down)).timerText)
                            .font(.caption).monospacedDigit()
                            .accessibilityElement(children: .combine)
                    }
                }
                Text("Skipped phases: \(runtime.skippedPhaseIDs.count)").font(.caption2)
                Text("Pauses and skipped time excluded.").font(.caption2).foregroundStyle(.secondary)
                if let error = model.healthSession.lastErrorMessage {
                    Text("Saved locally. Health unavailable: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(model.isFinishing ? "Saving workout…" : "Done") { model.closeRuntime() }
                    .disabled(model.isFinishing)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var phaseColor: Color {
        switch runtime.snapshot.phase.kind {
        case .warmup: .orange
        case .work: .red
        case .recovery: .blue
        case .cooldown: .mint
        }
    }
}

private extension WorkoutPhaseKind {
    var watchSummaryTitle: String {
        switch self {
        case .warmup: "Warmup"
        case .work: "Work / steady"
        case .recovery: "Recovery"
        case .cooldown: "Cooldown"
        }
    }
}
