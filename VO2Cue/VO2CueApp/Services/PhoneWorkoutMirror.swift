import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class PhoneWorkoutMirror: NSObject, HKWorkoutSessionDelegate {
    let heartRate = HeartRateFeed()
    private(set) var hasSession = false
    @ObservationIgnored var onState: ((WorkoutSessionState) -> Void)?
    @ObservationIgnored var onSessionReady: (() -> Void)?
    @ObservationIgnored var onEnded: ((Date) -> Void)?
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var currentSessionID: UUID?
    @ObservationIgnored private var commandTimeout: Task<Void, Never>?
    @ObservationIgnored private var pendingCommandID: UUID?
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    override init() {
        super.init()
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.attach(session) }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if let received = self.heartRate.receivedAt, Date().timeIntervalSince(received) > 4 {
                    self.heartRate.isConnected = false
                    self.heartRate.connectionMessage = "Watch connection delayed"
                }
            }
        }
    }

    func wakeWatch(profile: WorkoutProfile) async throws {
        let workout = HKWorkoutConfiguration()
        workout.activityType = profile.activity.healthKitType
        workout.locationType = profile.activity.locationType
        try await healthStore.startWatchApp(toHandle: workout)
    }

    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        session.delegate = self
        hasSession = true
        heartRate.connectionMessage = "Connecting to Apple Watch"
        heartRate.isConnected = false
        onSessionReady?()
        requestState()
    }

    func requestState() {
        guard let session else { return }
        Task { try? await WorkoutMessageDelivery.send(WorkoutSessionMessage(requestsState: true), using: session) }
    }

    func control(_ control: WorkoutControl, runtime: WorkoutRuntime) {
        guard let session, heartRate.isConnected, !heartRate.pendingCommand else {
            heartRate.lastCommandMessage = "Reconnect Apple Watch to control this workout. Your Watch keeps running."
            return
        }
        let command = RemoteWorkoutCommand(id: UUID(), sessionID: runtime.id, control: control,
            phaseID: runtime.snapshot.phase.id, issuedAt: Date())
        pendingCommandID = command.id
        heartRate.pendingCommand = true
        heartRate.lastCommandMessage = nil
        commandTimeout?.cancel()
        commandTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.pendingCommandID == command.id else { return }
            self.finishCommand(message: "Watch did not confirm this command. Check its current state before trying again.")
            self.requestState()
        }
        Task { [weak self] in
            do { try await WorkoutMessageDelivery.send(WorkoutSessionMessage(command: command), using: session) }
            catch {
                guard self?.pendingCommandID == command.id else { return }
                self?.finishCommand(message: "Command delivery could not be confirmed. Check Watch and try again.")
                self?.requestState()
            }
        }
    }

    private func finishCommand(message: String?) {
        commandTimeout?.cancel()
        pendingCommandID = nil
        heartRate.pendingCommand = false
        heartRate.lastCommandMessage = message
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap { try? JSONDecoder().decode(WorkoutSessionMessage.self, from: $0) }
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            for message in messages where message.version == 1 {
                if let state = message.state, state.isValid {
                    self.currentSessionID = state.sessionID
                    self.onState?(state)
                    if state.status == .completed || state.status == .ended { self.hasSession = false }
                }
                if let ack = message.acknowledgement, ack.id == self.pendingCommandID {
                    self.finishCommand(message: ack.message)
                }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            if toState == .ended {
                self.hasSession = false
                self.heartRate.isConnected = false
                self.heartRate.connectionMessage = "Workout ended on Apple Watch"
                self.finishCommand(message: nil)
                self.onEnded?(date)
                self.session = nil
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.session = nil
            self.heartRate.isConnected = false
            self.heartRate.connectionMessage = "Apple Watch disconnected · workout continues on Watch"
            self.finishCommand(message: nil)
            // Keep ownership until a new mirror or completed record arrives; do not start a competing phone timer.
        }
    }

    func receivedCompletedRecord(id: UUID) {
        if currentSessionID == id { hasSession = false }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        self.workoutSession(workoutSession, didDisconnectFromRemoteDeviceWithError: error)
    }
}
