import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [WorkoutProfile]
    private(set) var history: [WorkoutRecord]
    private(set) var watchSyncStatus: WatchProfileSyncStatus = .activating
    var finishedWorkoutForReview = false
    var activeRuntime: WorkoutRuntime?
    private(set) var isPreparingWorkout = false
    var workoutErrorMessage: String?
    var healthSavingEnabled: Bool {
        didSet { UserDefaults.standard.set(healthSavingEnabled, forKey: Self.healthSavingKey) }
    }

    let healthStore: HealthStore
    let purchases = PurchaseStore()
    let trainingProgress = TrainingProgressStore()
    let reminders = WorkoutReminderStore()
    let workoutMirror = PhoneWorkoutMirror()
    var heartRateSetupProfile: WorkoutProfile?
    var heartPreferences: HeartRatePreferences {
        didSet {
            try? Persistence.save(heartPreferences, fileName: "heart-preferences.json")
            connectivity.sync(heartPreferences: heartPreferences)
        }
    }
    @ObservationIgnored private var pendingWatchStartID: UUID?
    #if DEBUG
    @ObservationIgnored private var fixtureTask: Task<Void, Never>?
    #endif
    var selectedTab: AppTab = .workouts
    var workoutsNavigationPath: [UUID] = []
    private(set) var pendingWidgetWorkoutID: UUID?

    @ObservationIgnored private let workoutAudio = WorkoutAudioProgram()
    @ObservationIgnored private let liveActivity = WorkoutLiveActivity()
    @ObservationIgnored private var audioStatus: WorkoutRuntimeStatus = .idle
    @ObservationIgnored private let connectivity = PhoneWatchConnectivity()
    @ObservationIgnored private static let healthSavingKey = "healthSavingEnabled"
    @ObservationIgnored private static let lastWorkoutKey = "lastWidgetWorkoutID"

    init() {
        let savedProfiles = Persistence.load([WorkoutProfile].self, fileName: "profiles.json") ?? []
        profiles = savedProfiles.isEmpty ? [.norwegian4x4] : savedProfiles
        history = Persistence.load([WorkoutRecord].self, fileName: "history.json") ?? []
        healthSavingEnabled = UserDefaults.standard.object(forKey: Self.healthSavingKey) == nil
            ? true : UserDefaults.standard.bool(forKey: Self.healthSavingKey)
        healthStore = HealthStore()
        heartPreferences = Persistence.load(HeartRatePreferences.self, fileName: "heart-preferences.json") ?? .init()
        reminders.installNotificationHandler()

        connectivity.setRecordHandler { [weak self] record in
            self?.storeWatchRecord(record)
        }
        connectivity.setStatusHandler { [weak self] status in
            self?.watchSyncStatus = status
        }
        trainingProgress.onGoalChange = { [weak self] in self?.refreshWidgets() }
        workoutMirror.onState = { [weak self] state in self?.receiveWatchState(state) }
        workoutMirror.onSessionReady = { [weak self] in self?.liveActivity.prepareForMirroredWorkout() }
        workoutMirror.onEnded = { [weak self] date in
            guard let self, let runtime = self.activeRuntime, runtime.isMirrored,
                  runtime.status == .running || runtime.status == .paused else { return }
            runtime.finishMirror(at: date)
            self.liveActivity.update(runtime)
        }
        connectivity.sync(heartPreferences: heartPreferences)
        persistProfiles()
        #if DEBUG
        configureHeartSyncFixture()
        #endif
    }

    var completedSessions: Int {
        history.count(where: \.completed)
    }

    var totalActiveSeconds: Int {
        history.reduce(0) { $0 + ($1.actualActiveSeconds ?? 0) }
    }

    func profile(id: UUID) -> WorkoutProfile? {
        profiles.first { $0.id == id }
    }

    func upsert(_ profile: WorkoutProfile) {
        let profile = profile.sanitized
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistProfiles()
    }

    func duplicate(_ profile: WorkoutProfile) {
        var copy = WorkoutProfile(
            name: "\(profile.name) Copy",
            activity: profile.activity,
            warmupSeconds: profile.warmupSeconds,
            workSeconds: profile.workSeconds,
            recoverySeconds: profile.recoverySeconds,
            repeatCount: profile.repeatCount,
            cooldownSeconds: profile.cooldownSeconds,
            countdownSeconds: profile.countdownSeconds,
            hardCueLabel: profile.hardCueLabel,
            recoveryCueLabel: profile.recoveryCueLabel,
            cues: profile.cues,
            heartRateGuidance: profile.heartRateGuidance
        )
        copy = copy.sanitized
        profiles.append(copy)
        persistProfiles()
    }

    func deleteProfiles(ids: Set<UUID>) {
        profiles.removeAll { ids.contains($0.id) }
        if profiles.isEmpty { profiles = [.norwegian4x4] }
        persistProfiles()
    }

    func start(_ profile: WorkoutProfile) {
        if profile.heartRateGuidance?.enabled == true { startWithWatch(profile); return }
        startPhoneTimer(profile)
    }

    func startWithWatch(_ profile: WorkoutProfile, skipSetup: Bool = false) {
        guard purchases.isUnlocked, !isPreparingWorkout, activeRuntime == nil else { return }
        if !skipSetup, heartPreferences.confirmedMaximum == nil,
           profile.heartRateGuidance?.enabled != false,
           (profile.heartRateGuidance?.hardOverride?.isValid != true || profile.heartRateGuidance?.recoveryOverride?.isValid != true),
           !UserDefaults.standard.bool(forKey: "hasOfferedHeartRateSetup") {
            heartRateSetupProfile = profile
            return
        }
        isPreparingWorkout = true
        workoutErrorMessage = nil
        let id = UUID()
        pendingWatchStartID = id
        let resolved = profile.resolvingHeartRate(heartPreferences)
        Task {
            defer { isPreparingWorkout = false; pendingWatchStartID = nil }
            do {
                try await workoutMirror.wakeWatch(profile: resolved)
                let request = WatchWorkoutStartRequest(id: id, profile: resolved, expiresAt: Date().addingTimeInterval(40))
                try await connectivity.startWorkout(request)
                let deadline = Date().addingTimeInterval(12)
                while activeRuntime?.id != id, Date() < deadline {
                    try await Task.sleep(for: .milliseconds(200))
                }
                if activeRuntime?.id != id {
                    workoutErrorMessage = "Watch accepted the workout but live mirroring has not connected. Check Watch; its workout may already be running."
                }
            } catch {
                // A mirrored state may have arrived before the start acknowledgement.
                if activeRuntime?.id != id { workoutErrorMessage = error.localizedDescription }
            }
        }
    }

    func startPhoneTimer(_ profile: WorkoutProfile) {
        guard purchases.isUnlocked, !isPreparingWorkout, activeRuntime == nil else { return }
        guard !workoutMirror.hasSession else {
            workoutErrorMessage = "An Apple Watch workout is active or reconnecting. Finish it on Watch before starting a phone timer."
            return
        }
        isPreparingWorkout = true
        workoutErrorMessage = nil
        finishedWorkoutForReview = false
        Task {
            defer { isPreparingWorkout = false }
            let runtime = WorkoutRuntime(profile: profile) { [weak self] event in
                guard let self else { return }
                if case .finished(let completed) = event {
                    self.storeFinished(runtime: self.activeRuntime, completed: completed)
                }
            }
            do {
                try await workoutAudio.prepare(profile: runtime.profile, timeline: runtime.timeline)
                workoutAudio.onInterruption = { [weak self] in
                    guard let self, self.activeRuntime?.status == .running else { return }
                    self.activeRuntime?.pause()
                    self.workoutErrorMessage = "Workout paused because audio was interrupted. Resume when you’re ready."
                }
                workoutAudio.onPlaybackFinished = { [weak runtime] in runtime?.update() }
                activeRuntime = runtime
                UserDefaults.standard.set(profile.id.uuidString, forKey: Self.lastWorkoutKey)
                refreshWidgets()
                audioStatus = .idle
                runtime.changeHandler = { [weak self] runtime in self?.runtimeChanged(runtime) }
                runtime.start()
                liveActivity.start(runtime)
            } catch {
                workoutAudio.stop()
                workoutErrorMessage = error.localizedDescription
            }
        }
    }

    private func runtimeChanged(_ runtime: WorkoutRuntime) {
        let previousStatus = audioStatus
        audioStatus = runtime.status
        switch runtime.status {
        case .running:
            if previousStatus != .running {
                do { try workoutAudio.play(from: runtime.snapshot.elapsedSeconds) }
                catch {
                    runtime.pause()
                    workoutErrorMessage = "Audio could not start. Please check your audio output and resume."
                }
            }
        case .paused, .ended:
            workoutAudio.stop()
        case .completed:
            // Let the scheduled completion announcement finish before releasing audio.
            break
        case .idle: break
        }
        liveActivity.update(runtime)
    }

    func skipPhase() {
        guard let runtime = activeRuntime else { return }
        if runtime.isMirrored { workoutMirror.control(.skip, runtime: runtime); return }
        runtime.skip()
        if runtime.status == .running || runtime.status == .completed {
            do { try workoutAudio.play(from: runtime.snapshot.elapsedSeconds) }
            catch {
                runtime.pause()
                workoutErrorMessage = "Audio could not restart. Please check your audio output and resume."
            }
        }
    }

    func controlWorkout(_ control: WorkoutControl) {
        guard let runtime = activeRuntime else { return }
        if runtime.isMirrored { workoutMirror.control(control, runtime: runtime); return }
        switch control {
        case .pause: runtime.pause()
        case .resume: runtime.resume()
        case .skip: skipPhase()
        case .end: runtime.end()
        }
    }

    private func receiveWatchState(_ state: WorkoutSessionState) {
        guard state.isValid else { return }
        if let record = history.first(where: { $0.id == state.sessionID }) {
            workoutMirror.receivedCompletedRecord(id: record.id)
            if let runtime = activeRuntime, runtime.isMirrored, runtime.id == record.id {
                runtime.finishMirror(at: record.endedAt, record: record)
                liveActivity.update(runtime)
            }
            return
        }
        if let current = activeRuntime, current.id != state.sessionID {
            if current.isMirrored, current.status == .running || current.status == .paused { return }
            // Starting on Watch supersedes a phone timer rather than running two engines.
            if !current.isMirrored { current.end(); workoutAudio.stop() }
            activeRuntime = nil
        }
        if activeRuntime == nil {
            let runtime = WorkoutRuntime(profile: state.profile, id: state.sessionID, timeline: state.timeline, isMirrored: true)
            activeRuntime = runtime
            finishedWorkoutForReview = false
        }
        guard let runtime = activeRuntime, runtime.applyRemoteState(state) else { return }
        let feed = workoutMirror.heartRate
        feed.presentation = state.heartRate
        feed.receivedAt = Date()
        feed.sentAt = state.sentAt
        feed.isConnected = true
        feed.connectionMessage = "Apple Watch · Live workout"
        liveActivity.start(runtime)
    }

    func dismissRuntime() {
        workoutAudio.stop()
        activeRuntime = nil
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        trainingProgress.retainAnnotations(for: history)
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        trainingProgress.retainAnnotations(for: history)
        persistHistory()
    }

    private func storeFinished(runtime: WorkoutRuntime?, completed: Bool) {
        guard let record = runtime?.finishedRecord() else { return }
        finishedWorkoutForReview = completed
        appendRecordIfNeeded(record)
        if healthSavingEnabled {
            Task { await healthStore.save(record) }
        }
    }

    private func storeWatchRecord(_ record: WorkoutRecord) {
        appendRecordIfNeeded(record)
        workoutMirror.receivedCompletedRecord(id: record.id)
        if let runtime = activeRuntime, runtime.isMirrored, runtime.id == record.id {
            runtime.finishMirror(at: record.endedAt, record: record)
            liveActivity.update(runtime)
        }
    }

    private func appendRecordIfNeeded(_ record: WorkoutRecord) {
        guard !history.contains(where: { $0.id == record.id }) else { return }
        history.append(record)
        history.sort { $0.startedAt > $1.startedAt }
        persistHistory()
    }

    private func persistProfiles() {
        try? Persistence.save(profiles, fileName: "profiles.json")
        connectivity.sync(profiles: profiles)
        refreshWidgets()
    }

    func syncPurchaseAccess() {
        connectivity.sync(access: purchases.watchAccess)
    }

    private func persistHistory() {
        // A workout can finish while locked. Keep history encrypted, but allow
        // its completion record to be written after the first device unlock.
        try? Persistence.save(history, fileName: "history.json", protection: .completeFileProtectionUntilFirstUserAuthentication)
        refreshWidgets()
    }

    func refreshWidgets() {
        let lastID = UserDefaults.standard.string(forKey: Self.lastWorkoutKey).flatMap(UUID.init(uuidString:))
        let workout = lastID.flatMap { profile(id: $0) } ?? profiles.first
        let data = WeeklyGoalWidgetData(
            weeklyGoalMinutes: trainingProgress.weeklyGoalMinutes,
            sessions: history.compactMap { record in
                guard let seconds = record.actualActiveSeconds else { return nil }
                return .init(id: record.id, startedAt: record.startedAt, activeSeconds: seconds)
            },
            workout: workout.map { .init(id: $0.id, name: $0.name) }
        )
        do {
            try WeeklyGoalWidgetStore.save(data)
            WidgetCenter.shared.reloadTimelines(ofKind: WeeklyGoalWidgetStore.kind)
        } catch {
            // A missing App Group never prevents a workout or a history save.
            NSLog("Could not update weekly goal widget: %@", error.localizedDescription)
        }
    }

    func handleWidgetURL(_ url: URL) {
        guard let route = WorkoutWidgetRoute(url: url) else { return }
        pendingWidgetWorkoutID = nil
        switch route {
        case .progress:
            selectedTab = .progress
        case .workouts:
            selectedTab = .workouts
            workoutsNavigationPath.removeAll()
        case .startWorkout(let id):
            selectedTab = .workouts
            workoutsNavigationPath = profile(id: id) == nil ? [] : [id]
            // Never replace an existing session or queue a second start behind it.
            guard activeRuntime == nil, !isPreparingWorkout, profile(id: id) != nil else { return }
            pendingWidgetWorkoutID = id
        }
    }

    func startPendingWidgetWorkout(hasCompletedOnboarding: Bool) {
        guard hasCompletedOnboarding, purchases.isUnlocked, let id = pendingWidgetWorkoutID else { return }
        pendingWidgetWorkoutID = nil
        guard let profile = profile(id: id) else { return }
        start(profile)
    }

    #if DEBUG
    private func configureHeartSyncFixture() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-heartSyncFixture"), arguments.indices.contains(index + 1) else { return }
        let fixture = arguments[index + 1]
        let now = Date()
        var profile = WorkoutProfile.norwegian4x4
        profile.heartRateGuidance = HeartRateGuidance(maximumBPM: 180)
        if fixture == "phone" {
            let runtime = WorkoutRuntime(profile: profile)
            runtime.start(at: now)
            activeRuntime = runtime
            return
        }
        let isRecovery = fixture.hasPrefix("recovery")
        let readingBPM = fixture == "recoveryBelow" ? 100.0 : isRecovery ? 119.0 : 164.0
        let watch = WorkoutRuntime(profile: profile)
        let elapsed: Double = isRecovery ? 1_290 : 1_122
        watch.start(at: now.addingTimeInterval(-elapsed))
        for second in stride(from: 0.0, through: fixture == "watchNoSamples" ? -1 : elapsed - 2, by: 5) {
            let date = now.addingTimeInterval(second - elapsed)
            watch.update(at: date, emitCues: false)
            let kind = watch.snapshot.phase.kind
            let bpm = kind == .work ? 155 + 12 * sin(second / 40) : kind == .recovery ? 120 + 12 * cos(second / 25) : 105 + 10 * sin(second / 35)
            watch.recordHeartRate(.init(bpm: bpm, date: date), at: date)
        }
        watch.update(at: now)
        if fixture == "paused" { watch.pause(at: now) }
        let kind = watch.snapshot.phase.kind
        let sampleDate = fixture == "missing" ? now.addingTimeInterval(-20) : now
        let target = profile.heartRateGuidance?.target(for: kind)
        let reading = HeartRatePresentation(sample: fixture == "watchNoSamples" ? nil : .init(bpm: readingBPM, date: sampleDate),
            trendBPM: isRecovery ? 119 : 164, target: target,
            status: fixture == "paused" ? .paused : fixture == "watchNoSamples" ? .waiting : target?.status(for: readingBPM) ?? .monitoring)
        guard let state = watch.sessionState(revision: 1, heartRate: reading, at: now, includeTrace: true) else { return }
        let runtime = WorkoutRuntime(profile: profile, id: state.sessionID, timeline: state.timeline, isMirrored: true)
        _ = runtime.applyRemoteState(state, at: now)
        activeRuntime = runtime
        let feed = workoutMirror.heartRate
        feed.presentation = reading
        feed.isConnected = fixture != "disconnected"
        // Store captures use representative demo data with the normal product UI.
        // This launch path is compiled out of distribution builds.
        feed.isPreviewData = !arguments.contains("-appStoreScreenshots")
        feed.receivedAt = now
        feed.sentAt = now.addingTimeInterval(-0.05)
        feed.connectionMessage = "Simulated preview · Debug only"
        fixtureTask = Task { [weak self] in
            defer { watch.end() }
            var revision = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.activeRuntime?.id == runtime.id else { return }
                let currentDate = Date()
                var reading = reading
                if fixture != "missing", fixture != "watchNoSamples" {
                    reading.sample = HeartRateSample(bpm: readingBPM, date: currentDate)
                }
                if let sample = reading.sample { watch.recordHeartRate(sample, at: currentDate) }
                revision += 1
                if let next = watch.sessionState(revision: revision, heartRate: reading, at: currentDate) {
                    _ = runtime.applyRemoteState(next, at: currentDate)
                }
                feed.presentation = reading
                feed.receivedAt = currentDate
                feed.isConnected = fixture != "disconnected"
            }
        }
    }
    #endif
}

enum AppTab: Hashable {
    case workouts, progress, settings
}
