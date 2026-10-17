import Foundation
import Observation

enum WorkoutRuntimeStatus: Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
    case ended
}

enum WorkoutRuntimeEvent: Equatable, Sendable {
    case phaseChanged(WorkoutPhase)
    case countdown(Int)
    case halfway(WorkoutPhase)
    case finished(completed: Bool)
}

@MainActor
@Observable
final class WorkoutRuntime: Identifiable {
    let id = UUID()
    let profile: WorkoutProfile
    let timeline: WorkoutTimeline

    private(set) var status: WorkoutRuntimeStatus = .idle
    private(set) var snapshot: WorkoutSnapshot
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var phaseActiveSeconds: [TimeInterval]
    private(set) var skippedPhaseIDs: Set<UUID> = []

    @ObservationIgnored private var accumulatedElapsed: TimeInterval = 0
    @ObservationIgnored private var resumeAnchor: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastCountdownValue: Int?
    @ObservationIgnored private var halfwayPhaseIDs: Set<UUID> = []
    @ObservationIgnored var changeHandler: ((WorkoutRuntime) -> Void)?
    @ObservationIgnored private let eventHandler: (WorkoutRuntimeEvent) -> Void

    init(
        profile: WorkoutProfile,
        eventHandler: @escaping (WorkoutRuntimeEvent) -> Void = { _ in }
    ) {
        let cleanProfile = profile.sanitized
        let timeline = WorkoutTimeline(profile: cleanProfile)
        self.profile = cleanProfile
        self.timeline = timeline
        self.eventHandler = eventHandler
        self.snapshot = timeline.snapshot(at: 0)!
        self.phaseActiveSeconds = Array(repeating: 0, count: timeline.phases.count)
    }

    var elapsedSeconds: Int {
        Int(snapshot.elapsedSeconds.rounded(.down))
    }

    var actualActiveSeconds: Int {
        Int(phaseActiveSeconds.reduce(0, +).rounded(.down))
    }

    var phaseResults: [WorkoutPhaseResult] {
        timeline.phases.enumerated().map { index, phase in
            WorkoutPhaseResult(
                id: phase.id, kind: phase.kind, round: phase.round,
                label: phase.displayTitle, plannedSeconds: phase.durationSeconds,
                activeSeconds: phaseActiveSeconds[index], skipped: skippedPhaseIDs.contains(phase.id)
            )
        }
    }

    func finishedRecord() -> WorkoutRecord? {
        guard let startedAt, let endedAt, status == .completed || status == .ended else { return nil }
        return WorkoutRecord(
            id: id, profileID: profile.id, profileName: profile.name, activity: profile.activity,
            startedAt: startedAt, endedAt: endedAt, activeSeconds: actualActiveSeconds,
            completed: status == .completed, actualActiveSeconds: actualActiveSeconds, phaseResults: phaseResults
        )
    }

    var nextPhase: WorkoutPhase? {
        timeline.nextPhase(after: snapshot.phaseIndex)
    }

    func start(at date: Date = Date()) {
        guard status == .idle else { return }
        startedAt = date
        resumeAnchor = date
        status = .running
        eventHandler(.phaseChanged(snapshot.phase))
        startTicker()
        changeHandler?(self)
    }

    func pause(at date: Date = Date()) {
        guard status == .running else { return }
        update(at: date, emitCues: false)
        guard status == .running else { return }
        self.resumeAnchor = nil
        status = .paused
        ticker?.cancel()
        update(at: date, emitCues: false)
        changeHandler?(self)
    }

    func resume(at date: Date = Date()) {
        guard status == .paused else { return }
        resumeAnchor = date
        status = .running
        startTicker()
        changeHandler?(self)
    }

    func skip(at date: Date = Date()) {
        guard status == .running || status == .paused else { return }
        // Settle elapsed time first: a delayed tap may belong to a later phase.
        update(at: date, emitCues: false)
        guard status == .running || status == .paused else { return }
        skippedPhaseIDs.insert(snapshot.phase.id)
        let nextElapsed = TimeInterval(timeline.phaseEndSeconds(at: snapshot.phaseIndex))
        accumulatedElapsed = nextElapsed
        resumeAnchor = status == .running ? date : nil
        lastCountdownValue = nil
        update(at: date)
        changeHandler?(self)
    }

    func end(at date: Date = Date()) {
        guard status == .running || status == .paused else { return }
        update(at: date, emitCues: false)
        guard status == .running || status == .paused else { return }
        self.resumeAnchor = nil
        endedAt = date
        status = .ended
        ticker?.cancel()
        updateSnapshot(elapsed: min(accumulatedElapsed, TimeInterval(timeline.totalDurationSeconds)))
        eventHandler(.finished(completed: false))
        changeHandler?(self)
    }

    func update(at date: Date = Date(), emitCues: Bool = true) {
        guard status == .running || status == .paused else { return }
        let previousPhase = snapshot.phaseIndex
        let previousStatus = status
        defer {
            if snapshot.phaseIndex != previousPhase || status != previousStatus {
                changeHandler?(self)
            }
        }
        var completionDate = date
        if status == .running, let resumeAnchor {
            let delta = max(0, date.timeIntervalSince(resumeAnchor))
            let nextElapsed = min(accumulatedElapsed + delta, TimeInterval(timeline.totalDurationSeconds))
            // Distribute only actually traversed time across every crossed phase.
            for index in timeline.phases.indices {
                let start = TimeInterval(timeline.phaseStartSeconds(at: index))
                let end = TimeInterval(timeline.phaseEndSeconds(at: index))
                phaseActiveSeconds[index] += max(0, min(nextElapsed, end) - max(accumulatedElapsed, start))
            }
            if accumulatedElapsed + delta >= TimeInterval(timeline.totalDurationSeconds) {
                completionDate = resumeAnchor.addingTimeInterval(nextElapsed - accumulatedElapsed)
            }
            accumulatedElapsed = nextElapsed
            self.resumeAnchor = max(date, resumeAnchor)
        }

        if accumulatedElapsed >= TimeInterval(timeline.totalDurationSeconds) {
            accumulatedElapsed = TimeInterval(timeline.totalDurationSeconds)
            resumeAnchor = nil
            updateSnapshot(elapsed: accumulatedElapsed, emitCues: emitCues)
            endedAt = completionDate
            status = .completed
            ticker?.cancel()
            eventHandler(.finished(completed: true))
            return
        }

        updateSnapshot(elapsed: accumulatedElapsed, emitCues: emitCues)
    }

    private func updateSnapshot(elapsed: TimeInterval, emitCues: Bool = true) {
        guard let newSnapshot = timeline.snapshot(at: elapsed) else { return }
        let previous = snapshot
        snapshot = newSnapshot

        guard status == .running, emitCues else { return }

        if newSnapshot.phaseIndex != previous.phaseIndex {
            lastCountdownValue = nil
            eventHandler(.phaseChanged(newSnapshot.phase))
        }

        let countdown = newSnapshot.remainingSeconds
        if profile.countdownSeconds > 0,
           countdown > 0,
           countdown <= profile.countdownSeconds,
           countdown != lastCountdownValue {
            lastCountdownValue = countdown
            eventHandler(.countdown(countdown))
        }

        let halfway = Double(newSnapshot.phase.durationSeconds) / 2
        if profile.cues.halfwayCueEnabled,
           newSnapshot.phaseElapsedSeconds >= halfway,
           !halfwayPhaseIDs.contains(newSnapshot.phase.id) {
            halfwayPhaseIDs.insert(newSnapshot.phase.id)
            eventHandler(.halfway(newSnapshot.phase))
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                self.update()
            }
        }
    }
}
