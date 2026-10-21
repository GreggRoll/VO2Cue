import Foundation
import OSLog
import WatchConnectivity

enum WatchProfileSyncStatus: Equatable {
    case activating
    case queued
    case synced
    case watchUnavailable
    case watchAppNotInstalled
    case failed(String)

    var title: String {
        switch self {
        case .activating:
            "Preparing Apple Watch sync…"
        case .queued:
            "Latest workouts are queued for Apple Watch."
        case .synced:
            "Latest workouts synced to Apple Watch."
        case .watchUnavailable:
            "Pair an Apple Watch to sync workouts."
        case .watchAppNotInstalled:
            "Install VO2Cue on Apple Watch to sync workouts."
        case .failed:
            "Apple Watch sync will retry automatically."
        }
    }
}

@MainActor
final class PhoneWatchConnectivity: NSObject, WCSessionDelegate {
    private var recordHandler: ((WorkoutRecord) -> Void)?
    private var statusHandler: ((WatchProfileSyncStatus) -> Void)?
    private var pendingRecords: [WorkoutRecord] = []
    private var latestProfilesPayload: [String: Any] = [:]
    private var syncStatus: WatchProfileSyncStatus = .activating {
        didSet { statusHandler?(syncStatus) }
    }

    private let logger = Logger(subsystem: "com.gregadams.vo2cue", category: "WatchConnectivity")

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            syncStatus = .watchUnavailable
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func setRecordHandler(_ handler: @escaping (WorkoutRecord) -> Void) {
        recordHandler = handler
        pendingRecords.forEach(handler)
        pendingRecords.removeAll()
    }

    func setStatusHandler(_ handler: @escaping (WatchProfileSyncStatus) -> Void) {
        statusHandler = handler
        handler(syncStatus)
    }

    func sync(profiles: [WorkoutProfile]) {
        do {
            latestProfilesPayload.merge(try WatchConnectivityPayload.encodeProfiles(profiles)) { _, new in new }
            flushLatestProfiles()
        } catch {
            syncStatus = .failed(error.localizedDescription)
            logger.error("Could not encode workout profiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    func sync(access: WatchPurchaseAccess) {
        do {
            latestProfilesPayload.merge(try WatchConnectivityPayload.encodeAccess(access)) { _, new in new }
            flushLatestProfiles()
        } catch {
            logger.error("Could not encode purchase access: \(error.localizedDescription, privacy: .public)")
        }
    }

    func sync(heartPreferences: HeartRatePreferences) {
        guard let data = try? JSONEncoder().encode(heartPreferences) else { return }
        latestProfilesPayload[WatchConnectivityPayload.heartPreferencesKey] = data
        flushLatestProfiles()
    }

    func startWorkout(_ request: WatchWorkoutStartRequest) async throws {
        guard WCSession.isSupported(), WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else {
            throw WatchStartError.unavailable
        }
        while !WCSession.default.isReachable, Date() < request.expiresAt {
            try await Task.sleep(for: .milliseconds(300))
        }
        guard Date() < request.expiresAt else { throw WatchStartError.unreachable }
        let payload = [WatchConnectivityPayload.startRequestKey: try JSONEncoder().encode(request)]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WCSession.default.sendMessage(payload) { reply in
                if reply["accepted"] as? Bool == true { continuation.resume() }
                else { continuation.resume(throwing: WatchStartError.rejected(reply["message"] as? String ?? "Open VO2Cue on Apple Watch and try again.")) }
            } errorHandler: { error in continuation.resume(throwing: error) }
        }
    }

    private func flushLatestProfiles() {
        guard WCSession.isSupported(), !latestProfilesPayload.isEmpty else { return }
        let payload = latestProfilesPayload
        let session = WCSession.default

        guard session.activationState == .activated else {
            syncStatus = .activating
            session.activate()
            return
        }
        guard session.isPaired else {
            syncStatus = .watchUnavailable
            return
        }
        guard session.isWatchAppInstalled else {
            syncStatus = .watchAppNotInstalled
            return
        }

        do {
            try session.updateApplicationContext(payload)
            syncStatus = .queued
        } catch {
            syncStatus = .failed(error.localizedDescription)
            logger.error("Could not queue workout profiles: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard session.isReachable else { return }
        session.sendMessage(payload) { [weak self] reply in
            guard reply["received"] as? Bool == true else { return }
            Task { @MainActor [weak self] in
                self?.syncStatus = .synced
            }
        } errorHandler: { [weak self] error in
            self?.logger.debug("Immediate workout sync deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deliver(_ record: WorkoutRecord) {
        if let recordHandler {
            recordHandler(record)
        } else {
            pendingRecords.append(record)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.syncStatus = .failed(error.localizedDescription)
                self.logger.error("Watch session activation failed: \(error.localizedDescription, privacy: .public)")
            } else if activationState == .activated {
                self.flushLatestProfiles()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.flushLatestProfiles()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.flushLatestProfiles()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let record = WatchConnectivityPayload.decodeRecord(from: userInfo) else { return }
        Task { @MainActor [weak self] in
            self?.deliver(record)
        }
    }
}

enum WatchStartError: LocalizedError {
    case unavailable, unreachable, rejected(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Pair an Apple Watch and install VO2Cue on it first. You can still use the phone timer."
        case .unreachable: "Apple Watch did not connect. Open VO2Cue on your Watch, keep it nearby, and try again."
        case .rejected(let message): message
        }
    }
}
