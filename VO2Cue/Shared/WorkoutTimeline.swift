import Foundation

struct WorkoutSnapshot: Codable, Equatable, Sendable {
    let phaseIndex: Int
    let phase: WorkoutPhase
    let elapsedSeconds: TimeInterval
    let phaseElapsedSeconds: TimeInterval
    let remainingSeconds: Int
    let totalRemainingSeconds: Int
    let progress: Double
}

struct WorkoutTimeline: Codable, Equatable, Sendable {
    let phases: [WorkoutPhase]
    let totalDurationSeconds: Int

    init(profile: WorkoutProfile) {
        let profile = profile.sanitized
        var result: [WorkoutPhase] = []

        if profile.warmupSeconds > 0 {
            result.append(
                WorkoutPhase(
                    kind: .warmup,
                    durationSeconds: profile.warmupSeconds,
                    round: nil,
                    roundCount: profile.repeatCount,
                    cueLabel: "Warm up"
                )
            )
        }

        for round in 1...profile.repeatCount {
            result.append(
                WorkoutPhase(
                    kind: .work,
                    durationSeconds: profile.workSeconds,
                    round: round,
                    roundCount: profile.repeatCount,
                    cueLabel: profile.hardCueLabel
                )
            )

            if round < profile.repeatCount {
                result.append(
                    WorkoutPhase(
                        kind: .recovery,
                        durationSeconds: profile.recoverySeconds,
                        round: round,
                        roundCount: profile.repeatCount,
                        cueLabel: profile.recoveryCueLabel
                    )
                )
            }
        }

        if profile.cooldownSeconds > 0 {
            result.append(
                WorkoutPhase(
                    kind: .cooldown,
                    durationSeconds: profile.cooldownSeconds,
                    round: nil,
                    roundCount: profile.repeatCount,
                    cueLabel: "Cool down"
                )
            )
        }

        phases = result
        totalDurationSeconds = result.reduce(0) { $0 + $1.durationSeconds }
    }

    func snapshot(at elapsed: TimeInterval) -> WorkoutSnapshot? {
        guard let first = phases.first else { return nil }
        let clampedElapsed = min(max(0, elapsed), TimeInterval(totalDurationSeconds))
        var phaseStart = 0

        for (index, phase) in phases.enumerated() {
            let phaseEnd = phaseStart + phase.durationSeconds
            let isLast = index == phases.count - 1
            if clampedElapsed < TimeInterval(phaseEnd) || isLast {
                let phaseElapsed = min(
                    TimeInterval(phase.durationSeconds),
                    max(0, clampedElapsed - TimeInterval(phaseStart))
                )
                let remaining = max(0, Int(ceil(TimeInterval(phase.durationSeconds) - phaseElapsed)))
                return WorkoutSnapshot(
                    phaseIndex: index,
                    phase: phase,
                    elapsedSeconds: clampedElapsed,
                    phaseElapsedSeconds: phaseElapsed,
                    remainingSeconds: remaining,
                    totalRemainingSeconds: max(0, Int(ceil(TimeInterval(totalDurationSeconds) - clampedElapsed))),
                    progress: phase.durationSeconds == 0
                        ? 1
                        : min(1, max(0, phaseElapsed / TimeInterval(phase.durationSeconds)))
                )
            }
            phaseStart = phaseEnd
        }

        return WorkoutSnapshot(
            phaseIndex: 0,
            phase: first,
            elapsedSeconds: 0,
            phaseElapsedSeconds: 0,
            remainingSeconds: first.durationSeconds,
            totalRemainingSeconds: totalDurationSeconds,
            progress: 0
        )
    }

    func phaseStartSeconds(at index: Int) -> Int {
        phases.prefix(max(0, min(index, phases.count))).reduce(0) { $0 + $1.durationSeconds }
    }

    func phaseEndSeconds(at index: Int) -> Int {
        phaseStartSeconds(at: index) + phases[index].durationSeconds
    }

    func nextPhase(after index: Int) -> WorkoutPhase? {
        let nextIndex = index + 1
        guard phases.indices.contains(nextIndex) else { return nil }
        return phases[nextIndex]
    }
}
