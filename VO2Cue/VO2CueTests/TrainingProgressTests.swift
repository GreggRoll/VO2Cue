import XCTest

final class TrainingProgressTests: XCTestCase {
    private func record(at date: Date, seconds: Int?, id: UUID = UUID(), completed: Bool = false) -> WorkoutRecord {
        WorkoutRecord(id: id, profileID: UUID(), profileName: "Test", activity: .other,
                      startedAt: date, endedAt: date.addingTimeInterval(600), activeSeconds: 600,
                      completed: completed, actualActiveSeconds: seconds)
    }

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

    func testTemplateDurationsAndPhaseStructure() {
        XCTAssertEqual(WorkoutTemplate.allCases.map { $0.makeProfile().estimatedDuration }, [2100, 1320, 1200])
        for template in WorkoutTemplate.allCases {
            let profile = template.makeProfile()
            let timeline = WorkoutTimeline(profile: profile)
            XCTAssertEqual(timeline.totalDurationSeconds, profile.estimatedDuration)
            XCTAssertEqual(timeline.phases.filter { $0.kind == .recovery }.count, profile.repeatCount - 1)
            XCTAssertNotEqual(template.makeProfile().id, profile.id)
            XCTAssertNotEqual(profile.hardCueLabel, "Sprint")
        }
        XCTAssertEqual(WorkoutTimeline(profile: WorkoutTemplate.easy20.makeProfile()).phases.map(\.kind), [.warmup, .work, .cooldown])
    }

    func testLegacyJSONAndWatchPayloadRemainReadable() throws {
        let legacy = record(at: date(2026, 10, 11), seconds: nil)
        let data = try JSONEncoder.vo2Cue.encode(legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "actualActiveSeconds")
        object.removeValue(forKey: "phaseResults")
        let decoded = try JSONDecoder.vo2Cue.decode(WorkoutRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, legacy)
        XCTAssertNil(decoded.actualActiveSeconds)
        XCTAssertEqual(decoded.durationLabel, "Recorded time")
        let payload = try WatchConnectivityPayload.encodeRecord(decoded)
        XCTAssertEqual(WatchConnectivityPayload.decodeRecord(from: payload), legacy)
    }

    func testPartialWorkoutsCountAndLegacyAndDuplicatesDoNotInflateGoal() {
        let now = date(2026, 10, 11)
        let partial = record(at: now.addingTimeInterval(-600), seconds: 125)
        let complete = record(at: now.addingTimeInterval(-1200), seconds: 240, completed: true)
        let legacy = record(at: now, seconds: nil)
        let future = record(at: now.addingTimeInterval(600), seconds: 900)
        let weeks = TrainingProgress.weeks(records: [partial, partial, complete, legacy, future], now: now, calendar: calendar)
        XCTAssertEqual(weeks.count, 8)
        XCTAssertEqual(weeks.last?.activeSeconds, 365)
        XCTAssertEqual(weeks.dropLast().reduce(0) { $0 + $1.activeSeconds }, 0)
        XCTAssertEqual(TrainingProgress.weeks(records: [], now: now, calendar: calendar).map(\.activeSeconds), Array(repeating: 0, count: 8))
    }

    func testCalendarWeekBoundariesAndDaylightSaving() {
        let now = date(2026, 3, 8, hour: 23)
        let week = TrainingProgress.weeks(records: [], now: now, calendar: calendar).last!
        XCTAssertEqual(week.start, date(2026, 3, 2, hour: 0))
        XCTAssertEqual(week.end, date(2026, 3, 9, hour: 0))
        XCTAssertEqual(week.end.timeIntervalSince(week.start), 167 * 3600)
        let records = [record(at: week.start, seconds: 60),
                       record(at: week.start.addingTimeInterval(-1), seconds: 120),
                       record(at: week.end, seconds: 240)]
        let weeks = TrainingProgress.weeks(records: records, now: now, calendar: calendar)
        XCTAssertEqual(weeks.last?.activeSeconds, 60)
        XCTAssertEqual(weeks[6].activeSeconds, 120)
        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        XCTAssertEqual(TrainingProgress.weeks(records: [], now: now, calendar: sundayCalendar).last?.start,
                       date(2026, 3, 8, hour: 0))
    }

    func testAnnotationSanitizationPersistenceAndDeletion() throws {
        let first = record(at: date(2026, 10, 11), seconds: 60)
        let second = record(at: date(2026, 10, 11), seconds: 90)
        var preferences = TrainingPreferences()
        XCTAssertEqual(preferences.weeklyGoalMinutes, 60)
        preferences.setGoal(0)
        XCTAssertEqual(preferences.weeklyGoalMinutes, 1)
        preferences.setGoal(90)
        preferences.setAnnotation(WorkoutAnnotation(effort: 100, note: "  Felt good  "), for: first.id)
        preferences.setAnnotation(WorkoutAnnotation(effort: 5, note: "Other session"), for: second.id)
        preferences = try JSONDecoder.vo2Cue.decode(TrainingPreferences.self, from: JSONEncoder.vo2Cue.encode(preferences))
        XCTAssertEqual(preferences.annotations[first.id.uuidString]?.effort, 10)
        XCTAssertEqual(preferences.annotations[first.id.uuidString]?.note, "Felt good")
        preferences.retainAnnotations(for: [first])
        XCTAssertNil(preferences.annotations[second.id.uuidString])
        preferences.setAnnotation(WorkoutAnnotation(), for: first.id)
        XCTAssertTrue(preferences.annotations.isEmpty)
        XCTAssertEqual(TrainingProgress.weeks(records: [first], now: first.startedAt, calendar: calendar).last?.activeSeconds, 60)
        XCTAssertEqual(TrainingProgress.weeks(records: [], now: first.startedAt, calendar: calendar).last?.activeSeconds, 0)
    }
}

@MainActor
final class WorkoutActiveTimeTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    private func runtime() -> WorkoutRuntime {
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 10
        profile.workSeconds = 10
        profile.recoverySeconds = 5
        profile.repeatCount = 2
        profile.cooldownSeconds = 5
        return WorkoutRuntime(profile: profile)
    }

    func testSkipAndPausePreserveActualTrainingTime() throws {
        let runtime = runtime()
        runtime.start(at: start)
        runtime.skip(at: start.addingTimeInterval(3))
        XCTAssertEqual(runtime.elapsedSeconds, 10)
        XCTAssertEqual(runtime.actualActiveSeconds, 3)
        runtime.pause(at: start.addingTimeInterval(7))
        runtime.skip(at: start.addingTimeInterval(100))
        XCTAssertEqual(runtime.actualActiveSeconds, 7)
        XCTAssertEqual(runtime.snapshot.phase.kind, .recovery)
        runtime.resume(at: start.addingTimeInterval(100))
        runtime.end(at: start.addingTimeInterval(102))
        let record = try XCTUnwrap(runtime.finishedRecord())
        XCTAssertEqual(record.id, runtime.id)
        XCTAssertEqual(record.actualActiveSeconds, 9)
        XCTAssertFalse(record.completed)
        XCTAssertEqual(record.skippedPhaseCount, 2)
        XCTAssertEqual(record.phaseResults?.map(\.activeSeconds), [3, 4, 2, 0, 0])
        let payload = try WatchConnectivityPayload.encodeRecord(record)
        XCTAssertEqual(WatchConnectivityPayload.decodeRecord(from: payload), record)
    }

    func testDelayedUpdateDistributesTimeAndCapsNaturalCompletion() throws {
        let runtime = runtime()
        runtime.start(at: start)
        runtime.update(at: start.addingTimeInterval(29))
        XCTAssertEqual(runtime.phaseResults.map(\.activeSeconds), [10, 10, 5, 4, 0])
        runtime.update(at: start.addingTimeInterval(100))
        let record = try XCTUnwrap(runtime.finishedRecord())
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.actualActiveSeconds, 40)
        XCTAssertEqual(record.endedAt, start.addingTimeInterval(40))
        XCTAssertEqual(record.phaseResults?.map(\.activeSeconds), [10, 10, 5, 10, 5])
        runtime.update(at: start.addingTimeInterval(200))
        XCTAssertEqual(runtime.actualActiveSeconds, 40)
    }

    func testDelayedSkipSettlesCurrentPhaseBeforeSkipping() {
        let runtime = runtime()
        runtime.start(at: start)
        runtime.skip(at: start.addingTimeInterval(12))
        XCTAssertEqual(runtime.snapshot.phase.kind, .recovery)
        XCTAssertEqual(runtime.phaseResults.map(\.activeSeconds), [10, 2, 0, 0, 0])
        XCTAssertFalse(runtime.phaseResults[0].skipped)
        XCTAssertTrue(runtime.phaseResults[1].skipped)
        runtime.end(at: start.addingTimeInterval(12))
    }

    func testSkippingEveryPhaseDoesNotManufactureMinutes() {
        let runtime = runtime()
        runtime.start(at: start)
        for _ in 0..<5 { runtime.skip(at: start) }
        XCTAssertEqual(runtime.status, .completed)
        XCTAssertEqual(runtime.actualActiveSeconds, 0)
        XCTAssertEqual(runtime.skippedPhaseIDs.count, 5)
    }

    func testFractionalUpdatesDoNotLoseTimeAndBackwardClockDoesNotDuplicateIt() {
        let runtime = runtime()
        runtime.start(at: start)
        runtime.update(at: start.addingTimeInterval(0.4))
        runtime.update(at: start.addingTimeInterval(0.8))
        runtime.update(at: start.addingTimeInterval(1.2))
        runtime.update(at: start.addingTimeInterval(0.5))
        runtime.update(at: start.addingTimeInterval(2))
        XCTAssertEqual(runtime.actualActiveSeconds, 2)
        runtime.end(at: start.addingTimeInterval(2))
    }

    func testEndAfterScheduledFinishProducesOneNaturalCompletion() {
        var finishes = 0
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 0
        profile.workSeconds = 5
        profile.repeatCount = 1
        let runtime = WorkoutRuntime(profile: profile) { event in
            if case .finished = event { finishes += 1 }
        }
        runtime.start(at: start)
        runtime.end(at: start.addingTimeInterval(10))
        XCTAssertEqual(runtime.status, .completed)
        XCTAssertEqual(runtime.actualActiveSeconds, 5)
        XCTAssertEqual(finishes, 1)
    }
}
