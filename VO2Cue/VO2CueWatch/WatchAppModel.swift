import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class WatchAppModel {
    static let shared = WatchAppModel()
    private(set) var profiles: [WorkoutProfile]
    private(set) var history: [WorkoutRecord]
    var runtime: WorkoutRuntime?
    private(set) var isPreparing = false
    var startError: String?
    let heartRate = HeartRateFeed()
    let healthSession = WatchHealthSession()
    let purchases = PurchaseStore()
    private(set) var phoneAccess: WatchPurchaseAccess?
    private var heartPreferences = HeartRatePreferences()

    var hasWorkoutAccess: Bool {
        purchases.isUnlocked || phoneAccess?.allowsWorkout() == true || PurchaseConfiguration.paidDownloadCutoff == nil
    }

    @ObservationIgnored private let cues = CueCoordinator()
    @ObservationIgnored private let connectivity = WatchConnectivityStore()
    @ObservationIgnored private var coach = HeartRateCoach()
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var sender: Task<Void, Never>?
    @ObservationIgnored private var queuedState: WorkoutSessionState?
    @ObservationIgnored private var lastStateSendAt = Date.distantPast
    @ObservationIgnored private var lastTraceSendAt = Date.distantPast
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var commandGate = WorkoutCommandGate()
    @ObservationIgnored private var lastCheckpointAt = Date.distantPast
    @ObservationIgnored private var lastMirrorAttempt = Date.distantPast
    private(set) var isFinishing = false

    init() {
        let savedProfiles = Persistence.load([WorkoutProfile].self, fileName: "watch-profiles.json") ?? []
        profiles = savedProfiles.isEmpty ? [.norwegian4x4] : savedProfiles
        history = Persistence.load([WorkoutRecord].self, fileName: "watch-history.json") ?? []
        phoneAccess = Persistence.load(WatchPurchaseAccess.self, fileName: "watch-purchase-access.json")
        heartPreferences = Persistence.load(HeartRatePreferences.self, fileName: "watch-heart-preferences.json") ?? .init()
        connectivity.preferencesHandler = { [weak self] value in
            self?.heartPreferences = value
            try? Persistence.save(value, fileName: "watch-heart-preferences.json")
        }
        connectivity.setProfilesHandler { [weak self] profiles in
            self?.profiles = profiles
            try? Persistence.save(profiles, fileName: "watch-profiles.json")
        }
        connectivity.setAccessHandler { [weak self] access in
            self?.phoneAccess = access
            try? Persistence.save(access, fileName: "watch-purchase-access.json")
        }
        connectivity.startHandler = { [weak self] request in
            guard let self else { return (false, "Watch is unavailable.") }
            if self.runtime?.id == request.id { return (true, nil) }
            guard Date() < request.expiresAt else { return (false, "Start request expired. Try again.") }
            let started = await self.begin(request.profile, id: request.id, requireHealth: true, expiresAt: request.expiresAt)
            return (started, self.startError)
        }
        healthSession.onSample = { [weak self] sample in self?.refreshHeartRate(sample: sample) }
        healthSession.onState = { [weak self] state, date in
            guard let self, let runtime = self.runtime, !self.isFinishing else { return }
            switch state {
            case .paused: runtime.pause(at: date)
            case .running: if runtime.status == .paused { runtime.resume(at: date) }
            case .ended, .stopped: runtime.end(at: date)
            default: break
            }
        }
        healthSession.onMessage = { [weak self] message in self?.receive(message) }
        healthSession.onFailure = { [weak self] in self?.runtime?.pause() }
        #if DEBUG
        configureHeartSyncFixture()
        #endif
    }

    func start(_ profile: WorkoutProfile) {
        Task { _ = await begin(profile.resolvingHeartRate(heartPreferences), id: UUID(), requireHealth: false) }
    }

    private func begin(_ profile: WorkoutProfile, id: UUID, requireHealth: Bool, expiresAt: Date? = nil) async -> Bool {
        guard hasWorkoutAccess else { startError = "Open VO2Cue on iPhone to restore your workout access."; return false }
        guard !isPreparing, !isFinishing, runtime == nil || runtime?.status == .completed || runtime?.status == .ended else {
            startError = "A workout is already running on Apple Watch. Finish it before starting another."
            return false
        }
        isPreparing = true
        startError = nil
        defer { isPreparing = false }
        let prepared = await healthSession.prepare(profile: profile)
        if requireHealth && !prepared {
            startError = healthSession.lastErrorMessage ?? "Allow Health access on Apple Watch to start heart sync."
            return false
        }
        if let expiresAt, Date() >= expiresAt {
            healthSession.cancelPreparation()
            startError = "Start request expired while waiting for Health access. Try again."
            return false
        }
        coach = HeartRateCoach()
        revision = 0
        lastTraceSendAt = .distantPast
        commandGate = WorkoutCommandGate()
        heartRate.presentation = .init()
        let runtime = makeRuntime(profile: profile, id: id)
        self.runtime = runtime
        runtime.start()
        beginHeartbeat()
        if prepared, let startedAt = runtime.startedAt {
            await healthSession.begin(at: startedAt)
            publish()
        }
        return true
    }

    private func makeRuntime(profile: WorkoutProfile, id: UUID, timeline: WorkoutTimeline? = nil) -> WorkoutRuntime {
        let runtime = WorkoutRuntime(profile: profile, id: id, timeline: timeline) { [weak self] event in
            guard let self else { return }
            if case .halfway(let phase) = event,
               let guidanceCue = HeartRateHalfwayCue.resolve(presentation: self.coach.presentation,
                    phase: phase.kind, guidance: profile.heartRateGuidance, at: Date()) {
                self.cues.handleHalfwayHeartRate(guidanceCue, profile: profile)
            } else {
                self.cues.handle(event, profile: profile)
            }
            if case .finished = event { self.storeFinished() }
        }
        runtime.changeHandler = { [weak self] runtime in
            guard let self else { return }
            if runtime.status == .paused { self.healthSession.pause(); self.coach.resetAfterPause() }
            else if runtime.status == .running { self.healthSession.resume() }
            self.refreshHeartRate()
            self.checkpoint(force: true)
        }
        return runtime
    }

    func control(_ control: WorkoutControl) {
        guard let runtime, !isFinishing else { return }
        switch control {
        case .pause: runtime.pause()
        case .resume: coach.resetAfterPause(); runtime.resume()
        case .skip: runtime.skip()
        case .end: runtime.end()
        }
    }

    private func refreshHeartRate(sample: HeartRateSample? = nil) {
        guard let runtime, let startedAt = runtime.startedAt else { return }
        let cue = coach.update(sample: sample, snapshot: runtime.snapshot, running: runtime.status == .running,
            guidance: runtime.profile.heartRateGuidance, sessionStartedAt: startedAt, now: Date())
        heartRate.presentation = coach.presentation
        // A sample callback can cross the halfway point. Classify the newest reading
        // before recording advances the timer and emits that spoken cue.
        if let sample { runtime.recordHeartRate(sample) }
        if let cue { cues.handleHeartRate(cue, profile: runtime.profile) }
        publish()
    }

    private func beginHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshHeartRate()
                self.checkpoint(force: false)
                // HealthKit reconnects active mirrored sessions. Retry initial mirroring if no link was established.
                if !self.healthSession.isMirroring, self.healthSession.isActive,
                   Date().timeIntervalSince(self.lastMirrorAttempt) > 20 {
                    self.lastMirrorAttempt = Date()
                    Task { await self.healthSession.beginMirroring() }
                }
            }
        }
    }

    private func makeState(includeTrace: Bool = false) -> WorkoutSessionState? {
        revision += 1
        return runtime?.sessionState(revision: revision, heartRate: heartRate.presentation, includeTrace: includeTrace)
    }

    private func publish() {
        guard !isFinishing, let state = makeState(includeTrace: Date().timeIntervalSince(lastTraceSendAt) >= 10) else { return }
        queuedState = state
        guard sender == nil else { return }
        sender = Task { [weak self] in
            guard let self else { return }
            while let queued = self.queuedState, !Task.isCancelled {
                let byteCount = (try? JSONEncoder().encode(WorkoutSessionMessage(state: queued)).count) ?? 6_000
                // Frequent sensor callbacks and long profiles must not exhaust HealthKit's
                // transport quota. Coalesce while waiting, then send the newest snapshot.
                let interval = max(0.25, Double(byteCount) / 6_000)
                let delay = interval - Date().timeIntervalSince(self.lastStateSendAt)
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, !self.isFinishing, let state = self.queuedState else { break }
                self.queuedState = nil
                self.lastStateSendAt = Date()
                do {
                    try await self.healthSession.send(WorkoutSessionMessage(state: state))
                    if state.heartRateTrace != nil { self.lastTraceSendAt = Date() }
                }
                catch { break }
            }
            self.sender = nil
        }
    }

    private func receive(_ message: WorkoutSessionMessage) {
        if message.requestsState { publish() }
        guard let command = message.command, let runtime, command.sessionID == runtime.id else { return }
        let result = commandGate.evaluate(command, sessionID: runtime.id, phaseID: runtime.snapshot.phase.id,
            isActive: !isFinishing && (runtime.status == .running || runtime.status == .paused), now: Date())
        if result.execute { control(command.control) }
        acknowledge(result.acknowledgement)
    }

    private func acknowledge(_ ack: WorkoutCommandAcknowledgement) {
        let state = makeState()
        Task { try? await healthSession.send(WorkoutSessionMessage(state: state, acknowledgement: ack)) }
    }

    private func checkpoint(force: Bool) {
        guard !isFinishing, force || Date().timeIntervalSince(lastCheckpointAt) >= 10, let state = makeState(includeTrace: true) else { return }
        lastCheckpointAt = Date()
        try? Persistence.save(state, fileName: "watch-active-session.json", protection: .completeFileProtectionUntilFirstUserAuthentication)
    }

    func recoverActiveWorkout() {
        guard runtime == nil, !isPreparing else { return }
        isPreparing = true
        Task {
            defer { isPreparing = false }
            guard let recovered = await healthSession.recover() else { return }
            guard let state = Persistence.load(WorkoutSessionState.self, fileName: "watch-active-session.json"),
                  state.isValid, state.status == .running || state.status == .paused,
                  recovered == .running || recovered == .paused else {
                await healthSession.finish(at: Date())
                startError = "The workout could not be restored. Start a new workout when ready."
                return
            }
            revision = max(state.revision, Int(Date().timeIntervalSince1970 * 1_000))
            let runtime = makeRuntime(profile: state.profile, id: state.sessionID, timeline: state.timeline)
            self.runtime = runtime
            runtime.restorePrimary(state, running: recovered == .running)
            coach = HeartRateCoach()
            beginHeartbeat()
            refreshHeartRate()
        }
    }

    #if DEBUG
    private func configureHeartSyncFixture() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-heartSyncFixture"), arguments.indices.contains(index + 1) else { return }
        let fixture = arguments[index + 1]
        let now = Date()
        var profile = WorkoutProfile.heartSyncCheck
        profile.heartRateGuidance = .init(maximumBPM: 180)
        let preview = WorkoutRuntime(profile: profile)
        let elapsed = fixture.hasPrefix("recovery") ? 200.0 : 135.0
        let start = now.addingTimeInterval(-elapsed)
        preview.start(at: start)
        for second in stride(from: 0.0, through: elapsed - 2, by: 3) {
            let date = start.addingTimeInterval(second)
            let bpm = second < 30 ? 110 : second < 150 ? 155 + 10 * sin(second / 25) : 120
            preview.recordHeartRate(.init(bpm: bpm, date: date), at: date)
        }
        preview.update(at: now)
        self.runtime = preview
        heartRate.isPreviewData = true
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let date = Date()
                let sample = HeartRateSample(bpm: fixture == "recoveryBelow" ? 100 : fixture == "recovery" ? 119 : 164,
                    date: fixture == "missing" ? date.addingTimeInterval(-20) : date)
                preview.recordHeartRate(sample, at: date)
                _ = self.coach.update(sample: sample, snapshot: preview.snapshot, running: true,
                    guidance: profile.heartRateGuidance, sessionStartedAt: start, now: date)
                self.heartRate.presentation = self.coach.presentation
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    #endif

    func closeRuntime() { guard !isFinishing else { return }; runtime = nil }

    private func storeFinished() {
        guard !isFinishing, let record = runtime?.finishedRecord() else { return }
        isFinishing = true
        heartbeat?.cancel()
        if !history.contains(where: { $0.id == record.id }) {
            history.insert(record, at: 0)
            try? Persistence.save(history, fileName: "watch-history.json", protection: .completeFileProtectionUntilFirstUserAuthentication)
            connectivity.send(record: record)
        }
        let state = makeState(includeTrace: true)
        if let state { try? Persistence.save(state, fileName: "watch-active-session.json") }
        Task {
            if let state { try? await healthSession.send(WorkoutSessionMessage(state: state)) }
            await healthSession.finish(at: record.endedAt)
            isFinishing = false
        }
    }
}
