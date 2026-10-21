import SwiftUI

struct WatchRuntimeView: View {
    @Environment(WatchAppModel.self) private var model
    @Bindable var runtime: WorkoutRuntime
    @State private var confirmEnd = false
    @State private var page = 0

    var body: some View {
        NavigationStack {
            Group {
                if runtime.status == .completed || runtime.status == .ended {
                    completion
                } else {
                    TabView(selection: $page) {
                        timerPage.tag(0)
                        controlsPage.tag(1)
                        if !runtime.heartRateTrace.points.isEmpty {
                            ScrollView {
                                VStack(spacing: 8) {
                                    Button("Timer", systemImage: "timer") { page = 0 }
                                        .font(.caption2).buttonStyle(.plain)
                                    RuntimeIntervalGraph(runtime: runtime, showsTitle: false)
                                }.padding(.horizontal, 4)
                            }.tag(2)
                        }
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
            .navigationTitle(page == 0 && (runtime.status == .running || runtime.status == .paused)
                ? (model.heartRate.isPreviewData ? "\(runtime.snapshot.phase.displayTitle) · Debug" : runtime.snapshot.phase.displayTitle)
                : page == 2 ? "Timeline" : "Workout")
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd) {
            Button("End workout", role: .destructive) { model.control(.end) }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var timerPage: some View {
        ScrollView {
        VStack(spacing: 2) {
            if let round = runtime.snapshot.phase.roundDescription {
                Text(round)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(runtime.snapshot.remainingSeconds.timerText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Time remaining")
                .accessibilityValue(runtime.snapshot.remainingSeconds.timerText)
            if runtime.heartRateTrace.points.isEmpty {
                WatchHeartRateReadout(feed: model.heartRate, runtime: runtime)
            } else {
                Button { page = 2 } label: {
                    WatchHeartRateReadout(feed: model.heartRate, runtime: runtime)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show workout timeline")
                .accessibilityIdentifier("watchHeartRateTimeline")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        }
        .contentMargins(.top, 0, for: .scrollContent)
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
                RuntimeIntervalGraph(runtime: runtime)
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
