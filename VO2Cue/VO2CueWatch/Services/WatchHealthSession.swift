import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class WatchHealthSession: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private(set) var isActive = false
    private(set) var lastErrorMessage: String?
    private(set) var isMirroring = false
    @ObservationIgnored var onSample: ((HeartRateSample) -> Void)?
    @ObservationIgnored var onState: ((HKWorkoutSessionState, Date) -> Void)?
    @ObservationIgnored var onMessage: ((WorkoutSessionMessage) -> Void)?
    @ObservationIgnored var onFailure: (() -> Void)?
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    func prepare(profile: WorkoutProfile) async -> Bool {
        guard await requestAuthorization() else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = profile.activity.healthKitType
        configuration.locationType = profile.activity.locationType
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            attach(session)
            session.prepare()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func attach(_ session: HKWorkoutSession, recovering: Bool = false) {
        self.session = session
        let builder = session.associatedWorkoutBuilder()
        if !recovering || builder.dataSource == nil {
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
        }
        session.delegate = self
        builder.delegate = self
        self.builder = builder
    }

    func begin(at date: Date) async {
        guard let session, let builder else { return }
        session.startActivity(with: date)
        isActive = true
        do { try await builder.beginCollection(at: date) }
        catch { lastErrorMessage = error.localizedDescription }
        guard self.session === session else { return }
        await beginMirroring()
    }

    func beginMirroring() async {
        guard let session else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let completion = MirroringCompletion(continuation)
                session.startMirroringToCompanionDevice { [weak self] success, error in
                    Task { @MainActor in
                        if self?.session === session { self?.isMirroring = success }
                        completion.finish(error: success ? nil : (error ?? CocoaError(.fileWriteUnknown)))
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    completion.finish(error: CocoaError(.userCancelled))
                }
            }
        } catch {
            if self.session === session { isMirroring = false }
            // A standalone workout remains usable without a companion connection.
        }
    }

    func pause() { if session?.state == .running { session?.pause() } }
    func resume() { if session?.state == .paused { session?.resume() } }
    func cancelPreparation() { session?.end(); session = nil; builder = nil }

    func send(_ message: WorkoutSessionMessage) async throws {
        guard let session, isMirroring else { throw CocoaError(.fileWriteUnknown) }
        try await WorkoutMessageDelivery.send(message, using: session)
    }

    func finish(at date: Date) async {
        guard let session, let builder else { return }
        // Detach first so the end callback cannot end a later workout.
        self.session = nil
        self.builder = nil
        session.end()
        isActive = false
        isMirroring = false
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
            lastErrorMessage = nil
        } catch { lastErrorMessage = error.localizedDescription }
    }

    func recover() async -> HKWorkoutSessionState? {
        do {
            guard let recovered = try await healthStore.recoverActiveWorkoutSession() else { return nil }
            attach(recovered, recovering: true)
            isActive = recovered.state == .running || recovered.state == .paused
            await beginMirroring()
            return recovered.state
        } catch { lastErrorMessage = error.localizedDescription; return nil }
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { lastErrorMessage = "Apple Health is unavailable."; return false }
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [workoutType, heartRateType])
            let allowed = healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized
            if !allowed { lastErrorMessage = "Allow VO2Cue to save workouts in Health to start a live Watch session." }
            // Read authorization is intentionally not inferred from write authorization.
            return allowed
        } catch { lastErrorMessage = error.localizedDescription; return false }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.isActive = toState == .running || toState == .paused
            self.onState?(toState, date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.lastErrorMessage = error.localizedDescription
            self.isActive = false
            self.onFailure?()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap { try? JSONDecoder().decode(WorkoutSessionMessage.self, from: $0) }
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            for message in messages where message.version == 1 { self.onMessage?(message) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.isMirroring = false
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(type),
              let statistics = workoutBuilder.statistics(for: type), let quantity = statistics.mostRecentQuantity(),
              let interval = statistics.mostRecentQuantityDateInterval() else { return }
        let sample = HeartRateSample(bpm: quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())), date: interval.end)
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.onSample?(sample)
        }
    }
}

@MainActor
private final class MirroringCompletion {
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
