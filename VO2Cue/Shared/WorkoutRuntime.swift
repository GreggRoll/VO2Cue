import Foundation
import Observation

enum WorkoutRuntimeStatus: String, Codable, Equatable, Sendable {
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
    let id: UUID
    let isMirrored: Bool
    let profile: WorkoutProfile
    let timeline: WorkoutTimeline

    private(set) var status: WorkoutRuntimeStatus = .idle
    private(set) var snapshot: WorkoutSnapshot
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var phaseActiveSeconds: [TimeInterval]
    private(set) var skippedPhaseIDs: Set<UUID> = []
    private(set) var heartRateTrace = WorkoutHeartRateTrace()
    @ObservationIgnored private var heartRateNotBefore = Date.distantPast
    @ObservationIgnored private var lastHeartRateDate = Date.distantPast
    @ObservationIgnored private var breakHeartRateLine = false

    @ObservationIgnored private var accumulatedElapsed: TimeInterval = 0
    @ObservationIgnored private var resumeAnchor: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastCountdownValue: Int?
    @ObservationIgnored private var halfwayPhaseIDs: Set<UUID> = []
    @ObservationIgnored private var remoteState: WorkoutSessionState?
    @ObservationIgnored private(set) var remoteRevision = -1
    @ObservationIgnored var changeHandler: ((WorkoutRuntime) -> Void)?
    @ObservationIgnored private let eventHandler: (WorkoutRuntimeEvent) -> Void

    init(
        profile: WorkoutProfile,
        id: UUID = UUID(),
        timeline suppliedTimeline: WorkoutTimeline? = nil,
        isMirrored: Bool = false,
        eventHandler: @escaping (WorkoutRuntimeEvent) -> Void = { _ in }
    ) {
        let cleanProfile = profile.sanitized
        let timeline = suppliedTimeline ?? WorkoutTimeline(profile: cleanProfile)
        self.id = id
        self.isMirrored = isMirrored
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
            completed: status == .completed, actualActiveSeconds: actualActiveSeconds, phaseResults: phaseResults,
            heartRateTrace: heartRateTrace.points.isEmpty ? nil : heartRateTrace,
            heartRateGuidance: profile.heartRateGuidance
        )
    }

    var nextPhase: WorkoutPhase? {
        timeline.nextPhase(after: snapshot.phaseIndex)
    }

    func start(at date: Date = Date()) {
        guard !isMirrored else { return }
        guard status == .idle else { return }
        startedAt = date
        heartRateNotBefore = date
        resumeAnchor = date
        status = .running
        eventHandler(.phaseChanged(snapshot.phase))
        startTicker()
        changeHandler?(self)
    }

    func pause(at date: Date = Date()) {
        guard !isMirrored else { return }
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
        guard !isMirrored else { return }
        guard status == .paused else { return }
        resumeAnchor = date
        heartRateNotBefore = date
        breakHeartRateLine = true
        status = .running
        startTicker()
        changeHandler?(self)
    }

    func skip(at date: Date = Date()) {
        guard !isMirrored else { return }
        guard status == .running || status == .paused else { return }
        // Settle elapsed time first: a delayed tap may belong to a later phase.
        update(at: date, emitCues: false)
        guard status == .running || status == .paused else { return }
        heartRateNotBefore = date
        breakHeartRateLine = true
        skippedPhaseIDs.insert(snapshot.phase.id)
        let nextElapsed = TimeInterval(timeline.phaseEndSeconds(at: snapshot.phaseIndex))
        accumulatedElapsed = nextElapsed
        resumeAnchor = status == .running ? date : nil
        lastCountdownValue = nil
        update(at: date)
        changeHandler?(self)
    }

    func end(at date: Date = Date()) {
        guard !isMirrored else { return }
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
        if isMirrored {
            guard let remoteState, status == .running else { return }
            // Project briefly between heartbeats. A dropped link never runs a second workout engine.
            let delta = min(3, max(0, date.timeIntervalSince(remoteState.sentAt)))
            updateSnapshot(elapsed: min(remoteState.elapsed + delta, Double(timeline.totalDurationSeconds)), emitCues: false)
            return
        }
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

    func recordHeartRate(_ sample: HeartRateSample, at date: Date = Date()) {
        guard !isMirrored, status == .running, sample.isFresh(at: date),
              sample.date >= heartRateNotBefore, sample.date > lastHeartRateDate else { return }
        update(at: date)
        guard status == .running else { return }
        let elapsed = snapshot.elapsedSeconds
        let seconds = max(0, elapsed - max(0, date.timeIntervalSince(sample.date)))
        let previous = heartRateTrace.points.last
        heartRateTrace.append(seconds: seconds, bpm: sample.bpm, breakBefore: breakHeartRateLine)
        lastHeartRateDate = sample.date
        if heartRateTrace.points.last != previous { breakHeartRateLine = false }
    }

    func sessionState(revision: Int, heartRate: HeartRatePresentation, at date: Date = Date(), includeTrace: Bool = false) -> WorkoutSessionState? {
        guard let startedAt else { return nil }
        return WorkoutSessionState(sessionID: id, revision: revision, sentAt: date, profile: profile,
            timeline: timeline, status: status, startedAt: startedAt, endedAt: endedAt,
            elapsed: snapshot.elapsedSeconds, phaseActiveSeconds: phaseActiveSeconds,
            skippedPhaseIDs: skippedPhaseIDs, heartRate: heartRate,
            heartRatePoint: heartRateTrace.points.last,
            heartRateTrace: includeTrace ? heartRateTrace : nil)
    }

    @discardableResult
    func applyRemoteState(_ state: WorkoutSessionState, at date: Date = Date()) -> Bool {
        guard isMirrored, state.isValid, state.sessionID == id, state.revision > remoteRevision,
              state.timeline == timeline else { return false }
        if endedAt != nil, state.status == .running || state.status == .paused { return false }
        remoteRevision = state.revision
        remoteState = state
        startedAt = state.startedAt
        endedAt = state.endedAt
        status = state.status
        accumulatedElapsed = state.elapsed
        phaseActiveSeconds = state.phaseActiveSeconds
        skippedPhaseIDs = state.skippedPhaseIDs
        if let trace = state.heartRateTrace { heartRateTrace = trace }
        if let point = state.heartRatePoint { heartRateTrace.merge(point) }
        updateSnapshot(elapsed: state.elapsed, emitCues: false)
        ticker?.cancel()
        if status == .running { startTicker(); update(at: date) }
        return true
    }

    // Restore the Watch's own checkpoint only after HealthKit recovers its active primary session.
    func restorePrimary(_ state: WorkoutSessionState, running: Bool, at date: Date = Date()) {
        guard !isMirrored, state.isValid, state.sessionID == id else { return }
        startedAt = state.startedAt
        accumulatedElapsed = state.elapsed
        phaseActiveSeconds = state.phaseActiveSeconds
        skippedPhaseIDs = state.skippedPhaseIDs
        if let trace = state.heartRateTrace { heartRateTrace = trace }
        if let point = state.heartRatePoint { heartRateTrace.merge(point) }
        heartRateNotBefore = date
        breakHeartRateLine = true
        status = running ? .running : .paused
        resumeAnchor = running ? state.sentAt : nil
        updateSnapshot(elapsed: state.elapsed, emitCues: false)
        update(at: date, emitCues: false)
        if status == .running { startTicker() }
    }

    func finishMirror(at date: Date, record: WorkoutRecord? = nil) {
        guard isMirrored else { return }
        endedAt = record?.endedAt ?? date
        status = record?.completed == true ? .completed : .ended
        if let trace = record?.heartRateTrace { heartRateTrace = trace }
        if let results = record?.phaseResults { phaseActiveSeconds = results.map(\.activeSeconds) }
        ticker?.cancel()
    }
}
