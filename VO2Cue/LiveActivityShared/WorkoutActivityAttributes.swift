import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseTitle: String
        var symbol: String
        var round: String?
        var nextPhase: String
        var phaseStart: Date
        var phaseEnd: Date
        var remainingSeconds: Int
        var isPaused: Bool
        var isFinished: Bool
    }

    var workoutName: String
}
