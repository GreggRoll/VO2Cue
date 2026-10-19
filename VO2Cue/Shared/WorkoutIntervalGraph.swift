import SwiftUI
import Charts

struct WorkoutGraphPhase: Identifiable, Equatable {
    let id: UUID
    let kind: WorkoutPhaseKind
    let label: String
    let start: Double
    let end: Double
    let target: HeartRateRange?

    static func make(results: [WorkoutPhaseResult], guidance: HeartRateGuidance?) -> [Self] {
        var elapsed = 0.0
        return results.map { phase in
            defer { elapsed += Double(phase.plannedSeconds) }
            return Self(id: phase.id, kind: phase.kind,
                label: phase.round.map { "\(phase.label) \($0)" } ?? phase.label,
                start: elapsed, end: elapsed + Double(phase.plannedSeconds),
                target: guidance?.enabled == true ? guidance?.target(for: phase.kind) : nil)
        }
    }

    var color: Color {
        switch kind {
        case .work: .orange
        case .recovery: .blue
        case .warmup: .yellow
        case .cooldown: .mint
        }
    }
}

struct WorkoutIntervalGraph: View, Equatable {
    let phases: [WorkoutGraphPhase]
    let trace: WorkoutHeartRateTrace
    let elapsed: Double
    var isLive = true
    @State private var selectedSeconds: Double?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phases == rhs.phases && lhs.trace == rhs.trace
            && lhs.elapsed == rhs.elapsed && lhs.isLive == rhs.isLive
    }

    private var total: Double { max(1, phases.last?.end ?? 1) }
    private var domain: ClosedRange<Double> {
        let values = trace.points.map(\.bpm) + phases.compactMap(\.target).flatMap { [$0.lower, $0.upper] }
        return Double(max(20, (values.min() ?? 90) - 15))...Double(min(270, (values.max() ?? 180) + 15))
    }
    private var selectedPoint: HeartRateTracePoint? {
        guard let selectedSeconds else { return nil }
        // Selection in a sensor gap never invents an interpolated reading.
        return trace.points.min(by: { abs($0.seconds - selectedSeconds) < abs($1.seconds - selectedSeconds) })
            .flatMap { abs($0.seconds - selectedSeconds) <= 15 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout timeline").font(.headline)
            chart
                #if os(watchOS)
                .frame(height: 110)
                .chartXAxis(.hidden)
                #else
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) { Text(Int(seconds).timerText) }
                        }
                    }
                }
                .chartXSelection(value: $selectedSeconds)
                #endif
                .chartXScale(domain: 0...total)
                .chartYScale(domain: domain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .accessibilityLabel("Workout cycles and heart rate")
                .accessibilityValue("\(trace.points.count) recorded readings. Dashed lines show lower and upper heart-rate targets. Time excludes pauses; skipped time has no readings.")
                .accessibilityIdentifier("workoutHeartRateGraph")
            #if os(iOS)
            HStack(spacing: 14) {
                Label("Hard", systemImage: "square.fill").foregroundStyle(.orange)
                Label("Recovery", systemImage: "square.fill").foregroundStyle(.blue)
                Label("BPM", systemImage: "waveform.path.ecg").foregroundStyle(.primary)
            }.font(.caption2)
            if let selectedSeconds {
                Text(selectedPoint.map { "\(Int($0.seconds).timerText) · \($0.bpm) BPM" }
                     ?? "\(Int(selectedSeconds).timerText) · No recorded reading")
                    .font(.caption).monospacedDigit()
            }
            Text(trace.points.isEmpty ? (isLive ? "Use Apple Watch to add measured heart rate to this timeline." : "No heart-rate readings were recorded for this workout.")
                 : "Dashed lines: target range · Tap the graph to inspect BPM.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Planned workout time · Pauses excluded · Gaps for missing readings and skipped time")
                .font(.caption2).foregroundStyle(.secondary)
            #else
            Text("Hard / recovery · dashed targets").font(.caption2).foregroundStyle(.secondary)
            #endif
        }
        #if os(iOS)
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 22))
        #endif
    }

    private var chart: some View {
        Chart {
            ForEach(phases) { phase in
                RectangleMark(xStart: .value("Start", phase.start), xEnd: .value("End", phase.end),
                              yStart: .value("Minimum", domain.lowerBound), yEnd: .value("Maximum", domain.upperBound))
                    .foregroundStyle(phase.color.opacity(0.12))
                    .accessibilityLabel(phase.label)
                    .accessibilityValue("\(Int(phase.start).timerText) to \(Int(phase.end).timerText)")
                if let target = phase.target {
                    RectangleMark(xStart: .value("Start", phase.start), xEnd: .value("End", phase.end),
                                  yStart: .value("Lower target", target.lower), yEnd: .value("Upper target", target.upper))
                        .foregroundStyle(.green.opacity(0.12))
                        .accessibilityHidden(true)
                    RuleMark(xStart: .value("Start", phase.start), xEnd: .value("End", phase.end), y: .value("Lower target", target.lower))
                        .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .accessibilityLabel("\(phase.label) lower target, \(target.lower) BPM")
                    RuleMark(xStart: .value("Start", phase.start), xEnd: .value("End", phase.end), y: .value("Upper target", target.upper))
                        .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .accessibilityLabel("\(phase.label) upper target, \(target.upper) BPM")
                }
            }
            ForEach(trace.points) { point in
                LineMark(x: .value("Workout time", point.seconds), y: .value("Heart rate", point.bpm),
                         series: .value("Continuous readings", point.segment))
                    .foregroundStyle(.primary).lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
                    .accessibilityLabel("\(Int(point.seconds).timerText), \(point.bpm) BPM")
            }
            if isLive {
                RuleMark(x: .value("Progress", min(total, max(0, elapsed))))
                    .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.5))
                    .accessibilityLabel("Current workout time, \(Int(elapsed).timerText)")
            }
            if let selectedSeconds {
                RuleMark(x: .value("Selection", selectedSeconds)).foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
    }
}

struct RuntimeIntervalGraph: View {
    let runtime: WorkoutRuntime
    var body: some View {
        if !runtime.heartRateTrace.points.isEmpty {
            WorkoutIntervalGraph(phases: WorkoutGraphPhase.make(results: runtime.phaseResults,
                guidance: runtime.profile.heartRateGuidance), trace: runtime.heartRateTrace,
                elapsed: Double(runtime.elapsedSeconds),
                isLive: runtime.status == .running || runtime.status == .paused)
                .equatable()
        }
    }
}
