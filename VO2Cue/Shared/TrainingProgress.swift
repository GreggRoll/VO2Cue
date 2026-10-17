import Foundation

struct WorkoutAnnotation: Codable, Equatable {
    var effort: Int?
    var note: String = ""

    var sanitized: Self {
        Self(effort: effort.map { min(10, max(1, $0)) },
             note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000)))
    }
}

struct TrainingPreferences: Codable, Equatable {
    var weeklyGoalMinutes: Int = 60
    var annotations: [String: WorkoutAnnotation] = [:]

    mutating func setGoal(_ minutes: Int) {
        weeklyGoalMinutes = min(10_080, max(1, minutes))
    }

    mutating func setAnnotation(_ annotation: WorkoutAnnotation, for id: UUID) {
        let clean = annotation.sanitized
        annotations[id.uuidString] = clean.effort == nil && clean.note.isEmpty ? nil : clean
    }

    mutating func retainAnnotations(for records: [WorkoutRecord]) {
        let ids = Set(records.map { $0.id.uuidString })
        annotations = annotations.filter { ids.contains($0.key) }
    }
}

struct TrainingWeek: Identifiable, Equatable {
    let start: Date
    let end: Date
    let activeSeconds: Int
    var id: Date { start }
    var minutes: Double { Double(activeSeconds) / 60 }
}

enum TrainingProgress {
    // Attribute a session to its start week. Legacy records never contribute.
    static func weeks(records: [WorkoutRecord], now: Date = Date(), calendar: Calendar = .current) -> [TrainingWeek] {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let uniqueRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        return (-7...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: current.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let seconds = uniqueRecords.reduce(0) { total, record in
                guard record.startedAt >= start, record.startedAt < end, record.startedAt <= now,
                      let actual = record.actualActiveSeconds else { return total }
                return total + max(0, actual)
            }
            return TrainingWeek(start: start, end: end, activeSeconds: seconds)
        }
    }
}
