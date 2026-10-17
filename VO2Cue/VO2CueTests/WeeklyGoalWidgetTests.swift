import XCTest

final class WeeklyGoalWidgetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testWidgetMatchesAppProgressIncludingPartialLegacyDuplicateAndFutureSessions() {
        let now = date(2026, 10, 11)
        func record(seconds: Int?, at start: Date) -> WorkoutRecord {
            WorkoutRecord(id: UUID(), profileID: UUID(), profileName: "Test", activity: .other,
                          startedAt: start, endedAt: start.addingTimeInterval(600),
                          activeSeconds: 600, completed: false, actualActiveSeconds: seconds)
        }
        let partial = record(seconds: 125, at: now.addingTimeInterval(-600))
        let records = [partial, partial, record(seconds: 240, at: now.addingTimeInterval(-1_200)),
                       record(seconds: nil, at: now), record(seconds: 900, at: now.addingTimeInterval(600))]
        let data = WeeklyGoalWidgetData(sessions: records.compactMap { record in
            record.actualActiveSeconds.map { .init(id: record.id, startedAt: record.startedAt, activeSeconds: $0) }
        })
        let progress = data.progress(at: now, calendar: calendar)
        XCTAssertEqual(progress.activeSeconds, TrainingProgress.weeks(records: records, now: now, calendar: calendar).last?.activeSeconds)
        XCTAssertEqual(progress.activeMinutes, 6)
        XCTAssertEqual(progress.percent, 10)
        XCTAssertFalse(progress.isComplete)
    }

    func testNextWeekResetsWithoutOpeningAppAcrossDaylightSaving() throws {
        let now = date(2026, 3, 8, hour: 23)
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now))
        XCTAssertEqual(week.duration, 167 * 3_600)
        let data = WeeklyGoalWidgetData(weeklyGoalMinutes: 60, sessions: [
            .init(id: UUID(), startedAt: week.start, activeSeconds: 3_600),
            .init(id: UUID(), startedAt: week.start.addingTimeInterval(-1), activeSeconds: 900)
        ])
        XCTAssertTrue(data.progress(at: now, calendar: calendar).isComplete)
        XCTAssertEqual(data.progress(at: week.end, calendar: calendar).activeSeconds, 0)
        XCTAssertFalse(data.progress(at: week.end, calendar: calendar).isComplete)
    }

    func testGoalCompletionPreservesExtraMinutesAndSanitizesInvalidGoals() throws {
        let now = date(2026, 10, 11)
        var data = WeeklyGoalWidgetData(weeklyGoalMinutes: 30, sessions: [
            .init(id: UUID(), startedAt: now, activeSeconds: 2_520),
            .init(id: UUID(), startedAt: now, activeSeconds: -100)
        ], workout: .init(id: UUID(), name: "Norwegian 4×4"))
        data = try JSONDecoder().decode(WeeklyGoalWidgetData.self, from: JSONEncoder().encode(data))
        let progress = data.progress(at: now, calendar: calendar)
        XCTAssertEqual(progress.activeMinutes, 42)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.percent, 100)
        XCTAssertTrue(progress.isComplete)
        data.weeklyGoalMinutes = 0
        XCTAssertEqual(data.progress(at: now, calendar: calendar).goalMinutes, 1)
        data.weeklyGoalMinutes = 20_000
        XCTAssertEqual(data.progress(at: now, calendar: calendar).goalMinutes, 10_080)
    }

    func testWidgetRoutesRoundTripAndRejectMalformedURLs() throws {
        for route in [WorkoutWidgetRoute.progress, .workouts, .startWorkout(UUID())] {
            XCTAssertEqual(WorkoutWidgetRoute(url: route.url), route)
        }
        for text in ["https://progress", "vo2cue://unknown", "vo2cue://progress/extra",
                     "vo2cue://start-workout", "vo2cue://start-workout/not-a-uuid",
                     "vo2cue://start-workout/\(UUID())/extra", "vo2cue://progress?start=true"] {
            XCTAssertNil(WorkoutWidgetRoute(url: try XCTUnwrap(URL(string: text))), text)
        }
    }
}
