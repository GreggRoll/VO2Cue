import Foundation
import Observation

@MainActor
@Observable
final class WatchAppModel {
    private(set) var profiles: [WorkoutProfile]
    private(set) var history: [WorkoutRecord]
    var runtime: WorkoutRuntime?

    let healthSession = WatchHealthSession()
    let purchases = PurchaseStore()
    private(set) var phoneAccess: WatchPurchaseAccess?

    var hasWorkoutAccess: Bool {
        purchases.isUnlocked || phoneAccess?.allowsWorkout() == true || PurchaseConfiguration.paidDownloadCutoff == nil
    }

    @ObservationIgnored private let cues = CueCoordinator()
    @ObservationIgnored private let connectivity = WatchConnectivityStore()

    init() {
        let savedProfiles = Persistence.load([WorkoutProfile].self, fileName: "watch-profiles.json") ?? []
        profiles = savedProfiles.isEmpty ? [.norwegian4x4] : savedProfiles
        history = Persistence.load([WorkoutRecord].self, fileName: "watch-history.json") ?? []
        phoneAccess = Persistence.load(WatchPurchaseAccess.self, fileName: "watch-purchase-access.json")

        connectivity.setProfilesHandler { [weak self] profiles in
            self?.profiles = profiles
            try? Persistence.save(profiles, fileName: "watch-profiles.json")
        }
        connectivity.setAccessHandler { [weak self] access in
            self?.phoneAccess = access
            try? Persistence.save(access, fileName: "watch-purchase-access.json")
        }
    }

    func start(_ profile: WorkoutProfile) {
        guard hasWorkoutAccess, runtime == nil else { return }
        let runtime = WorkoutRuntime(profile: profile) { [weak self] event in
            guard let self else { return }
            self.cues.handle(event, profile: profile)
            if case .finished = event {
                self.storeFinished()
            }
        }
        self.runtime = runtime
        runtime.start()
        if let startedAt = runtime.startedAt {
            Task { await healthSession.start(profile: profile, at: startedAt) }
        }
    }

    func closeRuntime() {
        runtime = nil
    }

    private func storeFinished() {
        guard let record = runtime?.finishedRecord() else { return }
        if !history.contains(where: { $0.id == record.id }) {
            history.insert(record, at: 0)
            try? Persistence.save(history, fileName: "watch-history.json")
            connectivity.send(record: record)
        }
        Task { await healthSession.finish(at: record.endedAt) }
    }
}
