import XCTest

final class WorkoutTimelineTests: XCTestCase {
    func testCustomProfilesRoundTripThroughWatchConnectivityPayload() throws {
        var customProfile = WorkoutProfile.norwegian4x4
        customProfile.name = "Pool intervals"
        customProfile.activity = .swimming
        customProfile.repeatCount = 6

        let payload = try WatchConnectivityPayload.encodeProfiles([customProfile])
        let decoded = try XCTUnwrap(WatchConnectivityPayload.decodeProfiles(from: payload))

        XCTAssertEqual(decoded, [customProfile])
    }

    func testDefaultWorkoutMatchesClassicFourByFour() {
        let profile = WorkoutProfile.norwegian4x4
        let timeline = WorkoutTimeline(profile: profile)

        XCTAssertEqual(timeline.phases.count, 8)
        XCTAssertEqual(timeline.totalDurationSeconds, 35 * 60)
        XCTAssertEqual(timeline.phases.map(\.kind), [
            .warmup,
            .work, .recovery,
            .work, .recovery,
            .work, .recovery,
            .work
        ])
        XCTAssertEqual(timeline.phases.filter { $0.kind == .work }.map(\.round), [1, 2, 3, 4])
        XCTAssertEqual(timeline.phases.last?.kind, .work)
    }

    func testCooldownAndNoWarmupProduceExpectedSchedule() {
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 0
        profile.repeatCount = 2
        profile.cooldownSeconds = 300

        let timeline = WorkoutTimeline(profile: profile)

        XCTAssertEqual(timeline.phases.map(\.kind), [.work, .recovery, .work, .cooldown])
        XCTAssertEqual(timeline.totalDurationSeconds, 240 + 180 + 240 + 300)
    }

    func testSnapshotChangesPhaseAtExactBoundary() throws {
        let timeline = WorkoutTimeline(profile: .norwegian4x4)

        let warmup = try XCTUnwrap(timeline.snapshot(at: 599.2))
        XCTAssertEqual(warmup.phase.kind, .warmup)
        XCTAssertEqual(warmup.remainingSeconds, 1)

        let work = try XCTUnwrap(timeline.snapshot(at: 600))
        XCTAssertEqual(work.phase.kind, .work)
        XCTAssertEqual(work.phase.round, 1)
        XCTAssertEqual(work.remainingSeconds, 240)
        XCTAssertEqual(work.progress, 0)
    }

    func testSnapshotClampsBeforeAndAfterTimeline() throws {
        let timeline = WorkoutTimeline(profile: .norwegian4x4)

        XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: -10)).elapsedSeconds, 0)
        let end = try XCTUnwrap(timeline.snapshot(at: 10_000))
        XCTAssertEqual(end.elapsedSeconds, TimeInterval(timeline.totalDurationSeconds))
        XCTAssertEqual(end.remainingSeconds, 0)
        XCTAssertEqual(end.totalRemainingSeconds, 0)
        XCTAssertEqual(end.progress, 1)
    }

    func testProfileSanitizationProtectsRuntimeBounds() {
        let profile = WorkoutProfile(
            name: "   ",
            warmupSeconds: -1,
            workSeconds: 0,
            recoverySeconds: 0,
            repeatCount: 100,
            cooldownSeconds: -20,
            countdownSeconds: 99,
            hardCueLabel: " ",
            recoveryCueLabel: " ",
            cues: CueSettings()
        ).sanitized

        XCTAssertEqual(profile.name, "Untitled workout")
        XCTAssertEqual(profile.warmupSeconds, 0)
        XCTAssertEqual(profile.workSeconds, 5)
        XCTAssertEqual(profile.recoverySeconds, 5)
        XCTAssertEqual(profile.repeatCount, 20)
        XCTAssertEqual(profile.cooldownSeconds, 0)
        XCTAssertEqual(profile.countdownSeconds, 10)
        XCTAssertEqual(profile.hardCueLabel, "Hard")
        XCTAssertEqual(profile.recoveryCueLabel, "Recover")
    }

    @MainActor
    func testRuntimePauseResumeUsesActiveTimeOnly() {
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 10
        profile.repeatCount = 1
        profile.workSeconds = 10
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let runtime = WorkoutRuntime(profile: profile)

        runtime.start(at: start)
        runtime.update(at: start.addingTimeInterval(4))
        runtime.pause(at: start.addingTimeInterval(4))
        runtime.update(at: start.addingTimeInterval(100))
        XCTAssertEqual(runtime.elapsedSeconds, 4)

        runtime.resume(at: start.addingTimeInterval(100))
        runtime.update(at: start.addingTimeInterval(103))
        XCTAssertEqual(runtime.elapsedSeconds, 7)
        runtime.end(at: start.addingTimeInterval(103))
    }

    @MainActor
    func testRuntimeEmitsCountdownTransitionHalfwayAndCompletion() {
        let profile = WorkoutProfile(
            name: "Test",
            warmupSeconds: 0,
            workSeconds: 6,
            recoverySeconds: 5,
            repeatCount: 1,
            cooldownSeconds: 0,
            countdownSeconds: 3,
            hardCueLabel: "Go",
            recoveryCueLabel: "Easy",
            cues: CueSettings(halfwayCueEnabled: true)
        )
        var events: [WorkoutRuntimeEvent] = []
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let runtime = WorkoutRuntime(profile: profile) { events.append($0) }

        runtime.start(at: start)
        runtime.update(at: start.addingTimeInterval(3.1))
        runtime.update(at: start.addingTimeInterval(4.1))
        runtime.update(at: start.addingTimeInterval(5.1))
        runtime.update(at: start.addingTimeInterval(6))

        XCTAssertTrue(events.contains { if case .phaseChanged = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .halfway = $0 { true } else { false } })
        XCTAssertTrue(events.contains(.countdown(3)))
        XCTAssertTrue(events.contains(.countdown(2)))
        XCTAssertTrue(events.contains(.countdown(1)))
        XCTAssertTrue(events.contains(.finished(completed: true)))
        XCTAssertEqual(runtime.status, .completed)
    }

    @MainActor
    func testSkipMovesToNextPhase() {
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 60
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let runtime = WorkoutRuntime(profile: profile)

        runtime.start(at: start)
        runtime.skip(at: start.addingTimeInterval(1))

        XCTAssertEqual(runtime.snapshot.phase.kind, .work)
        XCTAssertEqual(runtime.snapshot.phase.round, 1)
        runtime.end(at: start.addingTimeInterval(1))
    }
}

final class WorkoutCueScheduleTests: XCTestCase {
    func testScheduleIncludesTransitionsAndCompletionAtExactActiveTimes() {
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 10
        profile.workSeconds = 6
        profile.repeatCount = 1
        let timeline = WorkoutTimeline(profile: profile)
        let cues = WorkoutCueSchedule(profile: profile, timeline: timeline).cues
        XCTAssertEqual(cues.first?.time, 0)
        XCTAssertEqual(cues.first?.phrase, "Warm up")
        XCTAssertEqual(cues.first { $0.time == 10 }?.phrase, profile.hardCueLabel)
        XCTAssertEqual(cues.last?.time, 16)
        XCTAssertEqual(cues.last?.phrase, "Workout complete")
        XCTAssertEqual(cues.filter { $0.phrase == "1" }.map(\.time), [9, 15])
        XCTAssertEqual(Set(cues.map(\.time)).count, cues.count)
    }

    func testShortPhaseCountdownDoesNotPrecedeItsPhase() {
        var profile = WorkoutProfile.norwegian4x4
        profile.warmupSeconds = 0
        profile.workSeconds = 5
        profile.repeatCount = 1
        profile.countdownSeconds = 10
        let cues = WorkoutCueSchedule(profile: profile, timeline: WorkoutTimeline(profile: profile)).cues
        XCTAssertEqual(cues.first?.phrase, profile.hardCueLabel)
        XCTAssertFalse(cues.contains { $0.time < 0 })
        XCTAssertEqual(cues.filter { Int($0.phrase) != nil }.map(\.phrase), ["4", "3", "2", "1"])
    }

    @MainActor
    func testPauseDoesNotEmitCuesAndPublishesFrozenState() {
        var events: [WorkoutRuntimeEvent] = []
        var states: [WorkoutRuntimeStatus] = []
        let runtime = WorkoutRuntime(profile: .norwegian4x4) { events.append($0) }
        runtime.changeHandler = { states.append($0.status) }
        let start = Date()
        runtime.start(at: start)
        let originalCount = events.count
        runtime.pause(at: start.addingTimeInterval(598))
        runtime.update(at: start.addingTimeInterval(900))
        XCTAssertEqual(events.count, originalCount)
        XCTAssertEqual(runtime.snapshot.remainingSeconds, 2)
        XCTAssertEqual(states.last, .paused)
        runtime.resume(at: start.addingTimeInterval(900))
        runtime.update(at: start.addingTimeInterval(902))
        XCTAssertEqual(runtime.snapshot.phase.kind, .work)
        XCTAssertEqual(states.last, .running)
        runtime.end(at: start.addingTimeInterval(902))
        XCTAssertEqual(states.last, .ended)
    }
}
