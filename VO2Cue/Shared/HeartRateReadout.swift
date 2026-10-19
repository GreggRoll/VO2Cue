import SwiftUI

private extension HeartRateStatus {
    var tint: Color {
        switch self {
        case .inTarget: .green
        case .above, .below: .orange
        default: .secondary
        }
    }
}

#if os(watchOS)
struct WatchHeartRateReadout: View {
    let feed: HeartRateFeed
    let runtime: WorkoutRuntime
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let value = feed.presentation.visible(at: context.date, paused: runtime.status == .paused)
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red).font(.caption)
                    Text(value.sample.map { String(Int($0.bpm.rounded())) } ?? "—")
                        .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                }
                if value.status != .monitoring {
                    Label(value.status.title, systemImage: value.status.symbol)
                        .font(.caption2).foregroundStyle(value.status.tint)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                if let target = value.target {
                    HeartRateTargetMeter(sample: value.sample, target: target)
                    HStack(spacing: 3) {
                        Text("Target \(target.label) BPM")
                        Image(systemName: "chart.xyaxis.line").accessibilityHidden(true)
                    }.font(.caption2).foregroundStyle(.secondary)
                } else if runtime.profile.heartRateGuidance?.enabled != false,
                          runtime.snapshot.phase.kind == .work || runtime.snapshot.phase.kind == .recovery {
                    Text("Set maximum on iPhone").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
#elseif os(iOS)
struct HeartRateCard: View {
    let feed: HeartRateFeed
    let runtime: WorkoutRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var readingSize = 46.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let value = feed.presentation.visible(at: context.date, paused: runtime.status == .paused,
                                                  allowsLiveSamples: runtime.isMirrored)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("HEART RATE", systemImage: "heart.fill").font(.caption.weight(.semibold))
                    Spacer()
                    if let sample = value.sample, let max = runtime.profile.heartRateGuidance?.maximumBPM {
                        Text("\(Int((sample.bpm / Double(max) * 100).rounded()))% max").font(.caption)
                    }
                }.foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { reading(value); Spacer(); status(value) }
                    VStack(alignment: .leading, spacing: 10) { reading(value); status(value) }
                }
                if let target = value.target {
                    HeartRateTargetMeter(sample: value.sample, target: target)
                    HStack {
                        Text("Below")
                        Spacer()
                        Text("Target \(target.label)").fontWeight(.semibold)
                        Spacer()
                        Text("Above")
                    }.font(.caption2).foregroundStyle(.secondary)
                }
                if runtime.profile.heartRateGuidance == nil || value.status == .unconfigured {
                    Text("Set your maximum in Settings → Heart-rate targets before your next Watch workout.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if runtime.profile.heartRateGuidance?.cuesEnabled == true, let coaching = value.status.coaching {
                    Text(coaching).font(.subheadline)
                }
                if value.trendBPM != nil, value.target != nil {
                    Text("Status uses a recent 10-second trend.").font(.caption2).foregroundStyle(.secondary)
                }
                source(value, now: context.date)
            }
            .padding(18)
            .background(.background, in: .rect(cornerRadius: 22))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("heartRateCard")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: value.status)
        }
    }

    private func reading(_ value: HeartRatePresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value.sample.map { String(Int($0.bpm.rounded())) } ?? "—")
                .font(.system(size: readingSize, weight: .bold, design: .rounded)).monospacedDigit()
                .accessibilityLabel(value.sample.map { "\(Int($0.bpm.rounded())) beats per minute" } ?? "No current heart-rate reading")
                .accessibilityIdentifier("currentHeartRate")
            Text("BPM").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }

    private func status(_ value: HeartRatePresentation) -> some View {
        Label(value.status.title, systemImage: value.status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(value.status.tint)
            .padding(9)
            .background(value.status.tint.opacity(0.12), in: .rect(cornerRadius: 9))
            .accessibilityIdentifier("heartRateStatus")
    }

    @ViewBuilder private func source(_ value: HeartRatePresentation, now: Date) -> some View {
        if !runtime.isMirrored {
            Label("Phone timer · use Apple Watch for live heart rate", systemImage: "applewatch")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(feed.isPreviewData ? "Simulated preview · Debug only" : feed.isConnected ? (value.sample == nil ? "Apple Watch · \(value.status.title)" : "Apple Watch · Live")
                        : feed.connectionMessage, systemImage: feed.isConnected ? "applewatch" : "wifi.slash")
                if let sample = value.sample {
                    Text("Reading \(max(0, Int(now.timeIntervalSince(sample.date))))s ago")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

#endif

struct HeartRateTargetMeter: View {
    #if os(watchOS)
    private let meterHeight = 13.0
    #else
    private let meterHeight = 19.0
    #endif
    let sample: HeartRateSample?
    let target: HeartRateRange
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = Double(max(1, target.upper - target.lower))
            let position = sample.map { min(0.98, max(0.02, ($0.bpm - Double(target.lower) + span) / (3 * span))) }
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16)).frame(height: 9)
                Rectangle().fill(.green.opacity(0.55)).frame(width: width / 3, height: 9).offset(x: width / 3)
                if let position {
                    Capsule().fill(.primary).frame(width: 4, height: meterHeight).offset(x: width * position - 2)
                }
            }.frame(height: meterHeight)
        }
        .frame(height: meterHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart-rate range meter")
        .accessibilityValue(sample.map { sample in
            let direction = sample.bpm < Double(target.lower) ? "below target" : sample.bpm > Double(target.upper) ? "above target" : "in target"
            return "\(Int(sample.bpm.rounded())) BPM, \(direction). Target \(target.lower) to \(target.upper) BPM"
        } ?? "No fresh reading. Target \(target.lower) to \(target.upper) BPM")
        .accessibilityIdentifier("heartRateRangeMeter")
    }
}
