import Foundation

// Only the values needed by the widgets leave the app's private container.
// Workout notes, Health data, and full profiles stay in the app.
struct WeeklyGoalWidgetData: Codable, Equatable {
    struct Session: Codable, Equatable {
        let id: UUID
        let startedAt: Date
        let activeSeconds: Int
    }

    struct Workout: Codable, Equatable {
        let id: UUID
        let name: String
    }

    var weeklyGoalMinutes = 60
    var sessions: [Session] = []
    var workout: Workout?

    func progress(at date: Date, calendar: Calendar = .current) -> WeeklyGoalWidgetProgress {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        var seen = Set<UUID>()
        let seconds = sessions.reduce(0) { total, session in
            guard seen.insert(session.id).inserted, let interval,
                  session.startedAt >= interval.start, session.startedAt < interval.end,
                  session.startedAt <= date else { return total }
            return total + max(0, session.activeSeconds)
        }
        return WeeklyGoalWidgetProgress(activeSeconds: seconds, goalMinutes: min(10_080, max(1, weeklyGoalMinutes)))
    }
}

struct WeeklyGoalWidgetProgress: Equatable {
    let activeSeconds: Int
    let goalMinutes: Int

    var activeMinutes: Int { activeSeconds / 60 }
    var fraction: Double { min(1, Double(activeSeconds) / Double(goalMinutes * 60)) }
    var percent: Int { Int(fraction * 100) }
    var isComplete: Bool { activeSeconds >= goalMinutes * 60 }
}

enum WeeklyGoalWidgetStore {
    static let appGroup = "group.com.gregadams.vo2cue.shared"
    static let kind = "VO2CueWeeklyGoal"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "weekly-goal-widget.json")
    }

    static func load() -> WeeklyGoalWidgetData {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WeeklyGoalWidgetData.self, from: data) else {
            return WeeklyGoalWidgetData()
        }
        return snapshot
    }

    static func save(_ snapshot: WeeklyGoalWidgetData) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(snapshot)
        // Completion may be saved while the phone is locked.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

enum WorkoutWidgetRoute: Equatable {
    case progress
    case workouts
    case startWorkout(UUID)

    var url: URL {
        var components = URLComponents()
        components.scheme = "vo2cue"
        switch self {
        case .progress:
            components.host = "progress"
        case .workouts:
            components.host = "workouts"
        case .startWorkout(let id):
            components.host = "start-workout"
            components.path = "/\(id.uuidString)"
        }
        return components.url!
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "vo2cue", components.user == nil, components.password == nil,
              components.port == nil, components.query == nil, components.fragment == nil else { return nil }
        switch components.host {
        case "progress" where components.path.isEmpty:
            self = .progress
        case "workouts" where components.path.isEmpty:
            self = .workouts
        case "start-workout":
            let path = components.path.split(separator: "/")
            guard path.count == 1, let id = UUID(uuidString: String(path[0])),
                  components.path == "/\(path[0])" else { return nil }
            self = .startWorkout(id)
        default:
            return nil
        }
    }
}
