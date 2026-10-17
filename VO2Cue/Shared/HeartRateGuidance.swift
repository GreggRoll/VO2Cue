import Foundation
import Observation

struct HeartRateRange: Codable, Equatable, Sendable {
    var lower: Int
    var upper: Int
    var isValid: Bool { (30...250).contains(lower) && (30...250).contains(upper) && lower < upper }
    var label: String { "\(lower)–\(upper)" }
}

enum MaximumHeartRateSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case entered, measured, estimated
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct HeartRatePreferences: Codable, Equatable, Sendable {
    var maximumBPM: Int?
    var source: MaximumHeartRateSource = .entered
    var confirmedMaximum: Int? { maximumBPM.flatMap { (100...230).contains($0) ? $0 : nil } }
}

struct HeartRateGuidance: Codable, Equatable, Sendable {
    var enabled = true
    var cuesEnabled = true
    var hardOverride: HeartRateRange?
    var recoveryOverride: HeartRateRange?
    // Filled into the session's immutable profile snapshot at start; personal settings remain separate.
    var maximumBPM: Int?

    func target(for phase: WorkoutPhaseKind) -> HeartRateRange? {
        let custom = phase == .work ? hardOverride : recoveryOverride
        guard phase == .work || phase == .recovery else { return nil }
        if let custom, custom.isValid { return custom }
        guard let maximumBPM, (100...230).contains(maximumBPM) else { return nil }
        let fractions = phase == .work ? (0.85, 0.95) : (0.60, 0.70)
        return HeartRateRange(lower: Int((Double(maximumBPM) * fractions.0).rounded()),
                              upper: Int((Double(maximumBPM) * fractions.1).rounded()))
    }
}

extension WorkoutProfile {
    static var heartSyncCheck: WorkoutProfile {
        WorkoutProfile(id: UUID(uuidString: "0C25D517-E438-4B8D-B4A1-00CCEA446D45")!, name: "Heart Sync Check",
            warmupSeconds: 30, workSeconds: 120, recoverySeconds: 90, repeatCount: 2,
            cooldownSeconds: 30, countdownSeconds: 3, hardCueLabel: "Hard", recoveryCueLabel: "Recover",
            cues: CueSettings(tonesEnabled: false), heartRateGuidance: HeartRateGuidance())
    }

    func resolvingHeartRate(_ preferences: HeartRatePreferences) -> WorkoutProfile {
        var result = self
        result.heartRateGuidance?.maximumBPM = preferences.confirmedMaximum
        return result
    }
}

struct HeartRateSample: Codable, Equatable, Sendable {
    let bpm: Double
    let date: Date
    func isFresh(at now: Date) -> Bool {
        bpm.isFinite && (20...260).contains(bpm) && (-2...15).contains(now.timeIntervalSince(date))
    }
}

enum HeartRateStatus: String, Codable, Equatable, Sendable {
    case waiting, missing, paused, monitoring, unconfigured, building, settling, below, inTarget, above, easyRecovery
    var title: String {
        switch self {
        case .waiting: "Waiting for heart rate"
        case .missing: "No fresh reading"
        case .paused: "Workout paused"
        case .monitoring: "Heart rate"
        case .unconfigured: "Set your targets"
        case .building: "Building"
        case .settling: "Settling"
        case .below: "Below target"
        case .inTarget: "In target"
        case .above: "Above target"
        case .easyRecovery: "Keep recovery easy"
        }
    }
    var symbol: String {
        switch self {
        case .below: "arrow.up"
        case .above: "arrow.down"
        case .inTarget: "checkmark"
        case .building, .settling: "hourglass"
        case .missing, .waiting: "waveform.slash"
        default: "heart"
        }
    }
    var coaching: String? {
        switch self {
        case .below: "Build your effort gradually."
        case .above: "Ease your effort."
        case .inTarget: "Hold this effort."
        case .building: "Build gradually toward your target."
        case .settling: "Let your heart rate settle."
        case .easyRecovery: "Keep recovery easy."
        case .unconfigured: "Set a confirmed maximum or custom BPM ranges in your profile."
        default: nil
        }
    }
}

struct HeartRatePresentation: Codable, Equatable, Sendable {
    var sample: HeartRateSample?
    var trendBPM: Double?
    var target: HeartRateRange?
    var status: HeartRateStatus = .waiting

    func visible(at now: Date, paused: Bool = false, allowsLiveSamples: Bool = true) -> HeartRatePresentation {
        var result = self
        if !allowsLiveSamples {
            result.sample = nil
            result.trendBPM = nil
            result.target = nil
            result.status = paused ? .paused : .waiting
            return result
        }
        if paused || status == .paused {
            result.status = .paused
            result.sample = nil
            result.trendBPM = nil
        } else if let sample, !sample.isFresh(at: now) {
            result.sample = nil
            result.trendBPM = nil
            result.status = .missing
        }
        return result
    }
}

// The Watch evaluates the trend once. Both displays receive this same classification.
struct HeartRateCoach {
    private var samples: [HeartRateSample] = []
    private var phaseID: UUID?
    private var boundaryStatus: HeartRateStatus = .inTarget
    private var deviationSince: Date?
    private var deviation: HeartRateStatus?
    private var lastCueAt: Date?
    private var lastAcceptedAt: Date?
    private var samplesNotBefore = Date.distantPast
    private(set) var presentation = HeartRatePresentation()

    mutating func resetAfterPause(at date: Date = Date()) {
        samplesNotBefore = date
        samples.removeAll()
        deviationSince = nil
        deviation = nil
        presentation.sample = nil
        presentation.trendBPM = nil
    }

    mutating func update(sample: HeartRateSample? = nil, snapshot: WorkoutSnapshot,
                         running: Bool, guidance: HeartRateGuidance?, sessionStartedAt: Date,
                         now: Date) -> HeartRateStatus? {
        if phaseID != snapshot.phase.id {
            phaseID = snapshot.phase.id
            samples.removeAll()
            deviationSince = nil
            deviation = nil
            boundaryStatus = .inTarget
            // Leave space for the interval transition cue.
            lastCueAt = now
        }
        presentation.target = guidance?.enabled == true ? guidance?.target(for: snapshot.phase.kind) : nil
        guard running else {
            resetAfterPause(at: now)
            presentation.status = .paused
            return nil
        }
        var accepted = false
        if let sample, sample.isFresh(at: now), sample.date >= max(sessionStartedAt, samplesNotBefore),
           lastAcceptedAt == nil || sample.date > lastAcceptedAt! {
            lastAcceptedAt = sample.date
            samples.append(sample)
            presentation.sample = sample
            accepted = true
        }
        samples.removeAll { now.timeIntervalSince($0.date) > 10 }
        guard let latest = presentation.sample, latest.isFresh(at: now) else {
            presentation.status = presentation.sample == nil ? .waiting : .missing
            presentation.trendBPM = nil
            deviationSince = nil
            deviation = nil
            return nil
        }
        let trend = samples.isEmpty ? latest.bpm : samples.reduce(0) { $0 + $1.bpm } / Double(samples.count)
        presentation.trendBPM = trend
        guard guidance?.enabled == true else { presentation.status = .monitoring; return nil }
        guard snapshot.phase.kind == .work || snapshot.phase.kind == .recovery else {
            presentation.status = .monitoring
            return nil
        }
        guard let target = presentation.target else { presentation.status = .unconfigured; return nil }
        let margin = 3.0
        let next: HeartRateStatus
        if trend < Double(target.lower) - (boundaryStatus == .below ? 0 : margin) {
            next = .below
        } else if trend > Double(target.upper) + (boundaryStatus == .above ? 0 : margin) {
            next = .above
        } else if boundaryStatus == .below && trend < Double(target.lower) + margin {
            next = .below
        } else if boundaryStatus == .above && trend > Double(target.upper) - margin {
            next = .above
        } else {
            next = .inTarget
        }
        boundaryStatus = next
        var status = next
        if snapshot.phase.kind == .work, next == .below, snapshot.phaseElapsedSeconds < 90 { status = .building }
        if snapshot.phase.kind == .recovery {
            if next == .above, snapshot.phaseElapsedSeconds < 60 { status = .settling }
            if next == .below { status = .easyRecovery }
        }
        presentation.status = status
        guard status == .below || status == .above else {
            deviationSince = nil
            deviation = nil
            return nil
        }
        if deviation != status { deviation = status; deviationSince = now }
        guard accepted, guidance?.cuesEnabled == true,
              let deviationSince, now.timeIntervalSince(deviationSince) >= 10,
              lastCueAt == nil || now.timeIntervalSince(lastCueAt!) >= 45,
              snapshot.remainingSeconds > 5 else { return nil }
        lastCueAt = now
        return status
    }
}

@MainActor
@Observable
final class HeartRateFeed {
    var isPreviewData = false
    var presentation = HeartRatePresentation()
    var receivedAt: Date?
    var sentAt: Date?
    var isConnected = false
    var connectionMessage = "Waiting for Apple Watch"
    var pendingCommand = false
    var lastCommandMessage: String?

    var deliveryMilliseconds: Int? {
        guard let receivedAt, let sentAt else { return nil }
        return max(0, Int(receivedAt.timeIntervalSince(sentAt) * 1_000))
    }
}
