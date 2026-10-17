import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class WatchConnectivityStore: NSObject, WCSessionDelegate {
    private var profilesHandler: (([WorkoutProfile]) -> Void)?
    private var accessHandler: ((WatchPurchaseAccess) -> Void)?
    private var pendingAccess: WatchPurchaseAccess?
    private var pendingProfiles: [WorkoutProfile]?
    private let logger = Logger(subsystem: "com.gregadams.vo2cue.watchkitapp", category: "WatchConnectivity")

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func setProfilesHandler(_ handler: @escaping ([WorkoutProfile]) -> Void) {
        profilesHandler = handler

        if let pendingProfiles {
            deliver(pendingProfiles)
        } else if WCSession.isSupported() {
            receive(payload: WCSession.default.receivedApplicationContext)
        }
    }

    func send(record: WorkoutRecord) {
        guard WCSession.isSupported() else { return }

        do {
            let payload = try WatchConnectivityPayload.encodeRecord(record)
            WCSession.default.transferUserInfo(payload)
        } catch {
            logger.error("Could not encode workout record: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setAccessHandler(_ handler: @escaping (WatchPurchaseAccess) -> Void) {
        accessHandler = handler
        if let pendingAccess {
            handler(pendingAccess)
            self.pendingAccess = nil
        } else if WCSession.isSupported() {
            receive(payload: WCSession.default.receivedApplicationContext)
        }
    }

    private func deliver(_ profiles: [WorkoutProfile]) {
        guard !profiles.isEmpty else { return }
        pendingProfiles = nil
        profilesHandler?(profiles)
    }

    @discardableResult
    nonisolated private func receive(payload: [String: Any]) -> Bool {
        let profiles = WatchConnectivityPayload.decodeProfiles(from: payload)
        let access = WatchConnectivityPayload.decodeAccess(from: payload)
        guard profiles != nil || access != nil else { return false }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let profiles {
                if self.profilesHandler == nil { self.pendingProfiles = profiles }
                else { self.deliver(profiles) }
            }
            if let access {
                if let handler = self.accessHandler { handler(access) }
                else { self.pendingAccess = access }
            }
        }
        return true
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Watch session activation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard activationState == .activated else { return }
        receive(payload: session.receivedApplicationContext)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        receive(payload: applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(payload: message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler(["received": receive(payload: message)])
    }
}
