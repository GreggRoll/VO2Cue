import Foundation
import Observation

@MainActor
@Observable
final class TrainingProgressStore {
    private(set) var preferences: TrainingPreferences
    private(set) var errorMessage: String?
    @ObservationIgnored private let save: (TrainingPreferences) throws -> Void
    @ObservationIgnored var onGoalChange: (() -> Void)?

    init(preferences: TrainingPreferences? = nil, save: ((TrainingPreferences) throws -> Void)? = nil) {
        self.preferences = preferences ?? Persistence.load(TrainingPreferences.self, fileName: "training-preferences.json") ?? TrainingPreferences()
        self.save = save ?? { try Persistence.save($0, fileName: "training-preferences.json") }
    }

    var weeklyGoalMinutes: Int { preferences.weeklyGoalMinutes }

    func setGoal(_ minutes: Int) {
        var next = preferences
        next.setGoal(minutes)
        persist(next)
    }

    func annotation(for id: UUID) -> WorkoutAnnotation {
        preferences.annotations[id.uuidString] ?? WorkoutAnnotation()
    }

    func setAnnotation(_ annotation: WorkoutAnnotation, for id: UUID) {
        var next = preferences
        next.setAnnotation(annotation, for: id)
        persist(next)
    }

    func retainAnnotations(for records: [WorkoutRecord]) {
        var next = preferences
        next.retainAnnotations(for: records)
        persist(next)
    }

    private func persist(_ next: TrainingPreferences) {
        do {
            try save(next)
            let goalChanged = preferences.weeklyGoalMinutes != next.weeklyGoalMinutes
            preferences = next
            errorMessage = nil
            if goalChanged { onGoalChange?() }
        } catch {
            errorMessage = "Couldn’t save your progress settings. Please try again."
        }
    }
}
