import Foundation

/// The audible workout program, expressed in active workout time.
struct ScheduledWorkoutCue: Equatable, Sendable {
    let time: TimeInterval
    let phrase: String
    let frequency: Double
    let toneDuration: TimeInterval
}

struct WorkoutCueSchedule {
    let cues: [ScheduledWorkoutCue]

    init(profile: WorkoutProfile, timeline: WorkoutTimeline) {
        let profile = profile.sanitized
        var result: [ScheduledWorkoutCue] = []
        for (index, phase) in timeline.phases.enumerated() {
            let start = Double(timeline.phaseStartSeconds(at: index))
            let duration = Double(phase.durationSeconds)
            result.append(.init(time: start, phrase: phase.displayTitle,
                                frequency: phase.kind == .work ? 1_000 : 440,
                                toneDuration: phase.kind == .work ? 0.24 : 0.17))
            if profile.cues.halfwayCueEnabled {
                result.append(.init(time: start + duration / 2, phrase: "Halfway",
                                    frequency: 780, toneDuration: 0.12))
            }
            // Never speak the old phase's countdown at the next phase boundary.
            let countdown = min(profile.countdownSeconds, phase.durationSeconds - 1)
            if countdown > 0 {
                for value in stride(from: countdown, through: 1, by: -1) {
                    result.append(.init(time: start + duration - Double(value), phrase: String(value),
                                        frequency: 660, toneDuration: 0.09))
                }
            }
        }
        result.append(.init(time: Double(timeline.totalDurationSeconds), phrase: "Workout complete",
                            frequency: 880, toneDuration: 0.4))
        // A countdown wins when it coincides with a halfway cue.
        cues = result.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.reduce(into: []) { cues, item in
            if cues.last?.time == item.element.time { cues.removeLast() }
            cues.append(item.element)
        }
    }
}
