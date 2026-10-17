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
        reminders.installNotificationHandler()

        connectivity.setRecordHandler { [weak self] record in
            self?.storeWatchRecord(record)
        }
        connectivity.setStatusHandler { [weak self] status in
            self?.watchSyncStatus = status
        }
        trainingProgress.onGoalChange = { [weak self] in self?.refreshWidgets() }
        persistProfiles()
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
            cues: profile.cues
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
        guard purchases.isUnlocked, !isPreparingWorkout, activeRuntime == nil else { return }
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
        runtime.skip()
        if runtime.status == .running || runtime.status == .completed {
            do { try workoutAudio.play(from: runtime.snapshot.elapsedSeconds) }
            catch {
                runtime.pause()
                workoutErrorMessage = "Audio could not restart. Please check your audio output and resume."
            }
        }
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
}

enum AppTab: Hashable {
    case workouts, progress, settings
}
