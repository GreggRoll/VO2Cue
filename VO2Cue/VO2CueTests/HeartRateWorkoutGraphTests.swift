import XCTest

final class HeartRateWorkoutGraphTests: XCTestCase {
    func testAgeEstimateUsesRequestedFormulaAndRejectsInvalidAges() {
        XCTAssertEqual(HeartRatePreferences.estimatedMaximum(age: 40), 192)
        XCTAssertEqual(HeartRatePreferences.estimatedMaximum(age: 35), 196)
        XCTAssertEqual(HeartRatePreferences.estimatedMaximum(age: 100), 150)
        XCTAssertNil(HeartRatePreferences.estimatedMaximum(age: 0))
        XCTAssertNil(HeartRatePreferences.estimatedMaximum(age: 101))
    }

    func testWatchDefaultsGainTargetsWhileExplicitOptOutIsPreserved() {
        let profile = WorkoutProfile.norwegian4x4
        let preferences = HeartRatePreferences(maximumBPM: 180)
        XCTAssertEqual(profile.resolvingHeartRate(preferences).heartRateGuidance?.target(for: .work)?.lower, 153)
        XCTAssertNil(profile.heartRateGuidance)
        XCTAssertNil(profile.resolvingHeartRate(.init()).heartRateGuidance)
        var disabled = profile
        disabled.heartRateGuidance = .init(enabled: false)
        XCTAssertEqual(disabled.resolvingHeartRate(preferences).heartRateGuidance?.enabled, false)
    }

    func testHalfwayGuidanceUsesFreshTrendAndDoesNotPushEasyRecovery() {
        let now = Date()
        let guidance = HeartRateGuidance(maximumBPM: 180)
        var value = HeartRatePresentation(sample: .init(bpm: 160, date: now), trendBPM: 140, status: .building)
        XCTAssertEqual(HeartRateHalfwayCue.resolve(presentation: value, phase: .work, guidance: guidance, at: now), .up)
        value.trendBPM = 160
        XCTAssertEqual(HeartRateHalfwayCue.resolve(presentation: value, phase: .work, guidance: guidance, at: now), .good)
        value.trendBPM = 180
        XCTAssertEqual(HeartRateHalfwayCue.resolve(presentation: value, phase: .work, guidance: guidance, at: now), .down)
        value.trendBPM = 90
        XCTAssertEqual(HeartRateHalfwayCue.resolve(presentation: value, phase: .recovery, guidance: guidance, at: now), .good)
        XCTAssertNil(HeartRateHalfwayCue.resolve(presentation: value, phase: .work, guidance: guidance, at: now.addingTimeInterval(16)))
        XCTAssertNil(HeartRateHalfwayCue.resolve(presentation: value, phase: .warmup, guidance: guidance, at: now))
        XCTAssertNil(HeartRateHalfwayCue.resolve(presentation: value, phase: .work, guidance: .init(cuesEnabled: false, maximumBPM: 180), at: now))
        value.status = .paused
        XCTAssertNil(HeartRateHalfwayCue.resolve(presentation: value, phase: .work, guidance: guidance, at: now))
    }

    func testBoundedTraceRetainsWholeWorkoutAndSeparatesSensorGaps() throws {
        var trace = WorkoutHeartRateTrace()
        for second in stride(from: 0, through: 20_000, by: 2) { trace.append(seconds: Double(second), bpm: 160) }
        XCTAssertLessThanOrEqual(trace.points.count, WorkoutHeartRateTrace.capacity)
        XCTAssertEqual(trace.points.first?.seconds, 0)
        XCTAssertEqual(trace.points.last?.seconds, 20_000)
        XCTAssertTrue(trace.isValid)
        let previous = trace.points.last!.segment
        trace.append(seconds: 20_020, bpm: 130)
        XCTAssertEqual(trace.points.last?.segment, previous + 1)
        trace.append(seconds: 20_025, bpm: 135, breakBefore: true)
        XCTAssertEqual(trace.points.last?.segment, previous + 2)
        let count = trace.points.count
        trace.append(seconds: 20_025, bpm: 200)
        trace.append(seconds: 20_024, bpm: 200)
        trace.append(seconds: .nan, bpm: 150)
        trace.append(seconds: 20_030, bpm: 0)
        XCTAssertEqual(trace.points.count, count)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutHeartRateTrace.self, from: JSONEncoder().encode(trace)), trace)
    }

    @MainActor
    func testGraphCoordinatesExcludePausesAndLeaveSkippedTimeBlankAndMirrorBackfills() throws {
        let start = Date(timeIntervalSince1970: 100_000)
        var profile = WorkoutProfile.heartSyncCheck
        profile.heartRateGuidance = .init(maximumBPM: 180)
        let runtime = WorkoutRuntime(profile: profile)
        runtime.start(at: start)
        runtime.recordHeartRate(.init(bpm: 110, date: start.addingTimeInterval(10)), at: start.addingTimeInterval(10))
        runtime.pause(at: start.addingTimeInterval(12))
        runtime.recordHeartRate(.init(bpm: 180, date: start.addingTimeInterval(20)), at: start.addingTimeInterval(20))
        runtime.resume(at: start.addingTimeInterval(100))
        runtime.recordHeartRate(.init(bpm: 190, date: start.addingTimeInterval(99)), at: start.addingTimeInterval(101))
        XCTAssertEqual(runtime.heartRateTrace.points.count, 1)
        runtime.recordHeartRate(.init(bpm: 115, date: start.addingTimeInterval(102)), at: start.addingTimeInterval(102))
        XCTAssertEqual(runtime.heartRateTrace.points.last?.seconds, 14)
        XCTAssertEqual(runtime.heartRateTrace.points.last?.segment, 1)
        runtime.skip(at: start.addingTimeInterval(104))
        runtime.recordHeartRate(.init(bpm: 150, date: start.addingTimeInterval(106)), at: start.addingTimeInterval(106))
        XCTAssertEqual(runtime.heartRateTrace.points.last?.seconds, 32)
        XCTAssertEqual(runtime.heartRateTrace.points.last?.segment, 2)
        let state = try XCTUnwrap(runtime.sessionState(revision: 1, heartRate: .init(), at: start.addingTimeInterval(106), includeTrace: true))
        XCTAssertTrue(state.isValid)
        let mirror = WorkoutRuntime(profile: profile, id: runtime.id, timeline: runtime.timeline, isMirrored: true)
        XCTAssertTrue(mirror.applyRemoteState(state, at: state.sentAt))
        XCTAssertEqual(mirror.heartRateTrace, runtime.heartRateTrace)
        let restored = WorkoutRuntime(profile: profile, id: runtime.id, timeline: runtime.timeline)
        restored.restorePrimary(state, running: true, at: state.sentAt)
        XCTAssertEqual(restored.heartRateTrace, runtime.heartRateTrace)
        runtime.end(at: start.addingTimeInterval(110))
        let record = try XCTUnwrap(runtime.finishedRecord())
        XCTAssertEqual(record.heartRateTrace, runtime.heartRateTrace)
        XCTAssertEqual(WatchConnectivityPayload.decodeRecord(from: try WatchConnectivityPayload.encodeRecord(record)), record)
        mirror.finishMirror(at: record.endedAt, record: record)
        XCTAssertEqual(mirror.finishedRecord()?.heartRateTrace, record.heartRateTrace)
        restored.end(at: start.addingTimeInterval(110))
    }

    @MainActor
    func testResumeAtSameGraphCoordinateKeepsContinuityBreakForNextPoint() {
        let start = Date(timeIntervalSince1970: 100_000)
        let runtime = WorkoutRuntime(profile: .heartSyncCheck)
        runtime.start(at: start)
        runtime.recordHeartRate(.init(bpm: 120, date: start.addingTimeInterval(10)), at: start.addingTimeInterval(10))
        runtime.pause(at: start.addingTimeInterval(10))
        runtime.resume(at: start.addingTimeInterval(20))
        runtime.recordHeartRate(.init(bpm: 130, date: start.addingTimeInterval(20)), at: start.addingTimeInterval(20))
        runtime.recordHeartRate(.init(bpm: 135, date: start.addingTimeInterval(22)), at: start.addingTimeInterval(22))
        XCTAssertEqual(runtime.heartRateTrace.points.map(\.seconds), [10, 12])
        XCTAssertEqual(runtime.heartRateTrace.points.map(\.segment), [0, 1])
        runtime.end(at: start.addingTimeInterval(23))
    }

    @MainActor
    func testMaximumSizeTraceFitsRecordTransferAndRoutineStateStaysSmall() throws {
        let start = Date(timeIntervalSince1970: 100_000)
        var profile = WorkoutProfile.norwegian4x4
        profile.repeatCount = 20
        profile.heartRateGuidance = .init(maximumBPM: 180)
        let runtime = WorkoutRuntime(profile: profile)
        runtime.start(at: start)
        for second in stride(from: 0, through: 958, by: 2) {
            let date = start.addingTimeInterval(Double(second))
            runtime.recordHeartRate(.init(bpm: 160, date: date), at: date)
        }
        let routine = try XCTUnwrap(runtime.sessionState(revision: 1, heartRate: .init()))
        XCTAssertNil(routine.heartRateTrace)
        XCTAssertNotNil(routine.heartRatePoint)
        XCTAssertLessThan(try JSONEncoder().encode(WorkoutSessionMessage(state: routine)).count, 12_000)
        let snapshot = try XCTUnwrap(runtime.sessionState(revision: 2, heartRate: .init(), includeTrace: true))
        XCTAssertLessThan(try JSONEncoder().encode(WorkoutSessionMessage(state: snapshot)).count, 24_000)
        runtime.end(at: start.addingTimeInterval(960))
        let record = try XCTUnwrap(runtime.finishedRecord())
        XCTAssertLessThan(try JSONEncoder.vo2Cue.encode(record).count, 60_000)
        let decoded = try JSONDecoder.vo2Cue.decode(WorkoutRecord.self, from: JSONEncoder.vo2Cue.encode(record))
        XCTAssertEqual(decoded.heartRateTrace, record.heartRateTrace)
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.vo2Cue.encode(record)) as? [String: Any])
        legacyJSON.removeValue(forKey: "heartRateTrace")
        legacyJSON.removeValue(forKey: "heartRateGuidance")
        XCTAssertNil(try JSONDecoder.vo2Cue.decode(WorkoutRecord.self, from: JSONSerialization.data(withJSONObject: legacyJSON)).heartRateTrace)
    }
}
