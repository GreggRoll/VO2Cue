import Foundation

enum WorkoutTemplate: String, CaseIterable, Identifiable {
    case norwegian4x4, shortIntervals, easy20

    var id: String { rawValue }
    var title: String {
        switch self {
        case .norwegian4x4: "Norwegian 4×4"
        case .shortIntervals: "Short Intervals"
        case .easy20: "Easy 20"
        }
    }

    var explanation: String {
        switch self {
        case .norwegian4x4:
            "Four four-minute hard intervals with active recovery. Aim for controlled, repeatable effort rather than an all-out sprint."
        case .shortIntervals:
            "Two-minute intervals with active recovery, plus a warmup and cooldown when you want a shorter session."
        case .easy20:
            "Twenty minutes including a warmup, a steady middle, and a cooldown. Choose an easy effort you can sustain comfortably."
        }
    }

    func makeProfile() -> WorkoutProfile {
        switch self {
        case .norwegian4x4:
            WorkoutProfile(name: title, warmupSeconds: 600, workSeconds: 240, recoverySeconds: 180,
                           repeatCount: 4, cooldownSeconds: 0, countdownSeconds: 3,
                           hardCueLabel: "Hard", recoveryCueLabel: "Recover", cues: CueSettings())
        case .shortIntervals:
            WorkoutProfile(name: title, warmupSeconds: 300, workSeconds: 120, recoverySeconds: 120,
                           repeatCount: 4, cooldownSeconds: 180, countdownSeconds: 3,
                           hardCueLabel: "Hard", recoveryCueLabel: "Recover", cues: CueSettings())
        case .easy20:
            WorkoutProfile(name: title, activity: .other, warmupSeconds: 180, workSeconds: 840, recoverySeconds: 60,
                           repeatCount: 1, cooldownSeconds: 180, countdownSeconds: 3,
                           hardCueLabel: "Steady", recoveryCueLabel: "Recover", cues: CueSettings())
        }
    }
}
