import Foundation
import HealthKit

enum WorkoutActivity: String, CaseIterable, Codable, Identifiable, Sendable {
    case highIntensityIntervalTraining
    case swimming
    case running
    case cycling
    case rowing
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highIntensityIntervalTraining: "HIIT"
        case .swimming: "Swimming"
        case .running: "Running"
        case .cycling: "Cycling"
        case .rowing: "Rowing"
        case .other: "Other cardio"
        }
    }

    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .highIntensityIntervalTraining: .highIntensityIntervalTraining
        case .swimming: .swimming
        case .running: .running
        case .cycling: .cycling
        case .rowing: .rowing
        case .other: .other
        }
    }

    var locationType: HKWorkoutSessionLocationType {
        switch self {
        case .running, .cycling: .outdoor
        default: .indoor
        }
    }
}

struct CueSettings: Codable, Equatable, Sendable {
    var hapticsEnabled: Bool = true
    var tonesEnabled: Bool = true
    var voiceEnabled: Bool = true
    var halfwayCueEnabled: Bool = true
}

struct WorkoutProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var activity: WorkoutActivity
    var warmupSeconds: Int
    var workSeconds: Int
    var recoverySeconds: Int
    var repeatCount: Int
    var cooldownSeconds: Int
    var countdownSeconds: Int
    var hardCueLabel: String
    var recoveryCueLabel: String
    var cues: CueSettings
    var heartRateGuidance: HeartRateGuidance?

    init(
        id: UUID = UUID(),
        name: String,
        activity: WorkoutActivity = .highIntensityIntervalTraining,
        warmupSeconds: Int,
        workSeconds: Int,
        recoverySeconds: Int,
        repeatCount: Int,
        cooldownSeconds: Int,
        countdownSeconds: Int,
        hardCueLabel: String,
        recoveryCueLabel: String,
        cues: CueSettings,
        heartRateGuidance: HeartRateGuidance? = nil
    ) {
        self.id = id
        self.name = name
        self.activity = activity
        self.warmupSeconds = warmupSeconds
        self.workSeconds = workSeconds
        self.recoverySeconds = recoverySeconds
        self.repeatCount = repeatCount
        self.cooldownSeconds = cooldownSeconds
        self.countdownSeconds = countdownSeconds
        self.hardCueLabel = hardCueLabel
        self.recoveryCueLabel = recoveryCueLabel
        self.cues = cues
        self.heartRateGuidance = heartRateGuidance
    }

    static let norwegian4x4 = WorkoutProfile(
        name: "Norwegian 4×4",
        warmupSeconds: 10 * 60,
        workSeconds: 4 * 60,
        recoverySeconds: 3 * 60,
        repeatCount: 4,
        cooldownSeconds: 0,
        countdownSeconds: 3,
        hardCueLabel: "Hard",
        recoveryCueLabel: "Recover",
        cues: CueSettings()
    )

    var estimatedDuration: Int {
        warmupSeconds
            + (workSeconds * repeatCount)
            + (recoverySeconds * max(repeatCount - 1, 0))
            + cooldownSeconds
    }

    var sanitized: WorkoutProfile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled workout"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.warmupSeconds = max(0, warmupSeconds)
        copy.workSeconds = max(5, workSeconds)
        copy.recoverySeconds = max(5, recoverySeconds)
        copy.repeatCount = min(max(1, repeatCount), 20)
        copy.cooldownSeconds = max(0, cooldownSeconds)
        copy.countdownSeconds = min(max(0, countdownSeconds), 10)
        copy.hardCueLabel = hardCueLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Hard"
            : hardCueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.recoveryCueLabel = recoveryCueLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Recover"
            : recoveryCueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

extension WorkoutProfile {
    static func == (lhs: WorkoutProfile, rhs: WorkoutProfile) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.activity == rhs.activity
            && lhs.warmupSeconds == rhs.warmupSeconds
            && lhs.workSeconds == rhs.workSeconds
            && lhs.recoverySeconds == rhs.recoverySeconds
            && lhs.repeatCount == rhs.repeatCount
            && lhs.cooldownSeconds == rhs.cooldownSeconds
            && lhs.countdownSeconds == rhs.countdownSeconds
            && lhs.hardCueLabel == rhs.hardCueLabel
            && lhs.recoveryCueLabel == rhs.recoveryCueLabel
            && lhs.cues == rhs.cues
            && lhs.heartRateGuidance == rhs.heartRateGuidance
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum WorkoutPhaseKind: String, Codable, Equatable, Sendable {
    case warmup
    case work
    case recovery
    case cooldown

    var systemImage: String {
        switch self {
        case .warmup: "flame"
        case .work: "bolt.fill"
        case .recovery: "arrow.down.heart"
        case .cooldown: "wind"
        }
    }
}

struct WorkoutPhase: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: WorkoutPhaseKind
    let durationSeconds: Int
    let round: Int?
    let roundCount: Int
    let cueLabel: String

    init(
        id: UUID = UUID(),
        kind: WorkoutPhaseKind,
        durationSeconds: Int,
        round: Int?,
        roundCount: Int,
        cueLabel: String
    ) {
        self.id = id
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.round = round
        self.roundCount = roundCount
        self.cueLabel = cueLabel
    }

    var displayTitle: String {
        switch kind {
        case .warmup: "Warm up"
        case .work: cueLabel
        case .recovery: cueLabel
        case .cooldown: "Cool down"
        }
    }

    var roundDescription: String? {
        guard let round else { return nil }
        return "Round \(round) of \(roundCount)"
    }
}

struct WorkoutRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let profileID: UUID
    let profileName: String
    let activity: WorkoutActivity
    let startedAt: Date
    let endedAt: Date
    let activeSeconds: Int
    let completed: Bool
    // Absent on legacy records, whose duration may include skipped intervals.
    let actualActiveSeconds: Int?
    let phaseResults: [WorkoutPhaseResult]?
    let heartRateTrace: WorkoutHeartRateTrace?
    let heartRateGuidance: HeartRateGuidance?

    init(
        id: UUID = UUID(),
        profileID: UUID,
        profileName: String,
        activity: WorkoutActivity,
        startedAt: Date,
        endedAt: Date,
        activeSeconds: Int,
        completed: Bool,
        actualActiveSeconds: Int? = nil,
        phaseResults: [WorkoutPhaseResult]? = nil,
        heartRateTrace: WorkoutHeartRateTrace? = nil,
        heartRateGuidance: HeartRateGuidance? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.profileName = profileName
        self.activity = activity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.completed = completed
        self.actualActiveSeconds = actualActiveSeconds
        self.phaseResults = phaseResults
        self.heartRateTrace = heartRateTrace
        self.heartRateGuidance = heartRateGuidance
    }

    var displayedSeconds: Int { actualActiveSeconds ?? activeSeconds }
    var durationLabel: String { actualActiveSeconds == nil ? "Recorded time" : "Active time" }
    var skippedPhaseCount: Int { phaseResults?.count(where: \.skipped) ?? 0 }
}

struct WorkoutPhaseResult: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: WorkoutPhaseKind
    let round: Int?
    let label: String
    let plannedSeconds: Int
    let activeSeconds: TimeInterval
    let skipped: Bool
}

extension Duration {
    var timerText: String {
        let components = self.components
        let seconds = max(0, Int(components.seconds))
        return seconds.timerText
    }
}

extension Int {
    var timerText: String {
        let value = Swift.max(0, self)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
