import Foundation
import HealthKit

struct WorkoutSessionState: Codable, Equatable, Sendable {
    let sessionID: UUID
    let revision: Int
    let sentAt: Date
    let profile: WorkoutProfile
    let timeline: WorkoutTimeline
    let status: WorkoutRuntimeStatus
    let startedAt: Date
    let endedAt: Date?
    let elapsed: TimeInterval
    let phaseActiveSeconds: [TimeInterval]
    let skippedPhaseIDs: Set<UUID>
    let heartRate: HeartRatePresentation
    var heartRatePoint: HeartRateTracePoint? = nil
    var heartRateTrace: WorkoutHeartRateTrace? = nil

    var isValid: Bool {
        (heartRateTrace?.isValid ?? true)
        && (heartRatePoint?.isValid ?? true)
        && (heartRatePoint.map { $0.seconds <= elapsed } ?? true)
        && (heartRateTrace?.points.last.map { $0.seconds <= elapsed } ?? true)
        && revision >= 0 && elapsed.isFinite && elapsed >= 0 && elapsed <= Double(timeline.totalDurationSeconds)
        && !timeline.phases.isEmpty && timeline.phases.count == phaseActiveSeconds.count
        && timeline.phases.allSatisfy { $0.durationSeconds > 0 }
        && timeline.totalDurationSeconds == timeline.phases.reduce(0, { $0 + $1.durationSeconds })
        && phaseActiveSeconds.allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

enum WorkoutControl: String, Codable, Sendable { case pause, resume, skip, end }

struct RemoteWorkoutCommand: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let control: WorkoutControl
    let phaseID: UUID
    let issuedAt: Date
    func isCurrent(at now: Date) -> Bool { (-2...8).contains(now.timeIntervalSince(issuedAt)) }
}

struct WorkoutCommandAcknowledgement: Codable, Equatable, Sendable {
    let id: UUID
    let accepted: Bool
    let message: String?
}

struct WorkoutCommandGate {
    private var acknowledgements: [WorkoutCommandAcknowledgement] = []
    mutating func evaluate(_ command: RemoteWorkoutCommand, sessionID: UUID, phaseID: UUID,
                           isActive: Bool, now: Date) -> (acknowledgement: WorkoutCommandAcknowledgement, execute: Bool) {
        if let previous = acknowledgements.first(where: { $0.id == command.id }) { return (previous, false) }
        let accepted = command.sessionID == sessionID && command.isCurrent(at: now) && isActive
            && (command.control != .skip || command.phaseID == phaseID)
        let ack = WorkoutCommandAcknowledgement(id: command.id, accepted: accepted,
            message: accepted ? nil : "The workout changed or the command expired. Check Watch and try again.")
        acknowledgements.append(ack)
        acknowledgements = Array(acknowledgements.suffix(128))
        return (ack, accepted)
    }
}

struct WorkoutSessionMessage: Codable, Sendable {
    var version = 1
    var state: WorkoutSessionState?
    var command: RemoteWorkoutCommand?
    var acknowledgement: WorkoutCommandAcknowledgement?
    var requestsState = false
}

struct WatchWorkoutStartRequest: Codable, Sendable {
    let id: UUID
    let profile: WorkoutProfile
    let expiresAt: Date
}

struct WorkoutMessageBudget {
    private var sentBytes: [(date: Date, count: Int)] = []
    mutating func reserve(_ count: Int, priority: Bool, at now: Date) throws {
        sentBytes.removeAll { now.timeIntervalSince($0.date) >= 10 }
        let limit = priority ? 98_000 : 70_000
        guard count > 0, sentBytes.reduce(0, { $0 + $1.count }) + count <= limit else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        sentBytes.append((now, count))
    }
}

// HealthKit completion callbacks can be delayed during a dropped link. Bound each send and
// resolve its continuation once, without keeping workout completion or controls waiting forever.
@MainActor
enum WorkoutMessageDelivery {
    private static var budget = WorkoutMessageBudget()
    static func send(_ message: WorkoutSessionMessage, using session: HKWorkoutSession) async throws {
        let data = try JSONEncoder().encode(message)
        let priority = message.command != nil || message.acknowledgement != nil || message.requestsState
            || message.state?.status == .completed || message.state?.status == .ended
        // HealthKit allows 100 KB per ten seconds. Reserve room for controls and final state,
        // including profiles with twenty rounds. Routine heartbeats coalesce on the next tick.
        try budget.reserve(data.count, priority: priority, at: Date())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = SendCompletion(continuation)
            session.sendToRemoteWorkoutSession(data: data) { success, error in
                Task { @MainActor in completion.finish(error: success ? nil : (error ?? CocoaError(.fileWriteUnknown))) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                completion.finish(error: CocoaError(.userCancelled))
            }
        }
    }

    @MainActor private final class SendCompletion {
        var continuation: CheckedContinuation<Void, Error>?
        init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
        func finish(error: Error?) {
            guard let continuation else { return }
            self.continuation = nil
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }
}
