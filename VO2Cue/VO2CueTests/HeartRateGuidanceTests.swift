import XCTest

final class HeartRateGuidanceTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)
    private var guidance: HeartRateGuidance { HeartRateGuidance(maximumBPM: 180) }
    private func snapshot(_ phase: WorkoutPhaseKind = .work, seconds: Double = 100, id: UUID = UUID()) -> WorkoutSnapshot {
        let phase = WorkoutPhase(id: id, kind: phase, durationSeconds: 240, round: 1, roundCount: 4, cueLabel: "Custom")
        return WorkoutSnapshot(phaseIndex: 0, phase: phase, elapsedSeconds: seconds, phaseElapsedSeconds: seconds,
            remainingSeconds: 240 - Int(seconds), totalRemainingSeconds: 1_000, progress: seconds / 240)
    }

    func testTargetsRoundAndRespectOverridesAndWarmup() {
        XCTAssertEqual(guidance.target(for: .work), HeartRateRange(lower: 153, upper: 171))
        XCTAssertEqual(guidance.target(for: .recovery), HeartRateRange(lower: 108, upper: 126))
        XCTAssertNil(guidance.target(for: .warmup))
        XCTAssertNil(guidance.target(for: .cooldown))
        var custom = guidance
        custom.hardOverride = HeartRateRange(lower: 140, upper: 160)
        XCTAssertEqual(custom.target(for: .work), custom.hardOverride)
        custom.maximumBPM = nil
        XCTAssertEqual(custom.target(for: .work), custom.hardOverride)
        XCTAssertNil(custom.target(for: .recovery))
        XCTAssertEqual(HeartRateGuidance(maximumBPM: 181).target(for: .work), HeartRateRange(lower: 154, upper: 172))
    }

    func testLegacyProfileDecodesWithoutGuidanceAndNewProfileSyncs() throws {
        var profile = WorkoutProfile.norwegian4x4
        let legacy = try JSONEncoder.vo2Cue.encode(profile)
        XCTAssertNil(try JSONDecoder.vo2Cue.decode(WorkoutProfile.self, from: legacy).heartRateGuidance)
        profile.heartRateGuidance = guidance
        XCTAssertEqual(WatchConnectivityPayload.decodeProfiles(from: try WatchConnectivityPayload.encodeProfiles([profile])), [profile])
    }

    func testPersonalMaximumIsResolvedIntoSessionWithoutChangingSavedProfile() {
        var profile = WorkoutProfile.norwegian4x4
        profile.heartRateGuidance = .init()
        let resolved = profile.resolvingHeartRate(.init(maximumBPM: 180, source: .measured))
        XCTAssertNil(profile.heartRateGuidance?.maximumBPM)
        XCTAssertEqual(resolved.heartRateGuidance?.maximumBPM, 180)
        XCTAssertNil(HeartRatePreferences(maximumBPM: 0).confirmedMaximum)
    }

    func testTransitionStatesAndBelowTargetRecovery() {
        var coach = HeartRateCoach()
        _ = coach.update(sample: .init(bpm: 120, date: start), snapshot: snapshot(seconds: 20), running: true,
            guidance: guidance, sessionStartedAt: start.addingTimeInterval(-20), now: start)
        XCTAssertEqual(coach.presentation.status, .building)
        _ = coach.update(sample: .init(bpm: 170, date: start.addingTimeInterval(1)), snapshot: snapshot(.recovery, seconds: 10), running: true,
            guidance: guidance, sessionStartedAt: start.addingTimeInterval(-20), now: start.addingTimeInterval(1))
        XCTAssertEqual(coach.presentation.status, .settling)
        _ = coach.update(sample: .init(bpm: 90, date: start.addingTimeInterval(12)), snapshot: snapshot(.recovery, seconds: 90), running: true,
            guidance: guidance, sessionStartedAt: start.addingTimeInterval(-20), now: start.addingTimeInterval(12))
        XCTAssertEqual(coach.presentation.status, .below)
    }

    func testHighWorkIsVisibleDuringBuildingWindowAndRawNumberIsPreserved() {
        var coach = HeartRateCoach()
        let sample = HeartRateSample(bpm: 184, date: start)
        _ = coach.update(sample: sample, snapshot: snapshot(seconds: 10), running: true, guidance: guidance,
                         sessionStartedAt: start.addingTimeInterval(-10), now: start)
        XCTAssertEqual(coach.presentation.status, .above)
        XCTAssertEqual(coach.presentation.sample, sample)
    }

    func testStaleOutOfOrderAndPreviousSessionSamplesNeverBecomeLive() {
        var coach = HeartRateCoach()
        let phase = snapshot()
        _ = coach.update(sample: .init(bpm: 160, date: start.addingTimeInterval(-1)), snapshot: phase,
            running: true, guidance: guidance, sessionStartedAt: start, now: start)
        XCTAssertNil(coach.presentation.sample)
        _ = coach.update(sample: .init(bpm: 160, date: start), snapshot: phase,
            running: true, guidance: guidance, sessionStartedAt: start, now: start)
        _ = coach.update(sample: .init(bpm: 190, date: start.addingTimeInterval(-1)), snapshot: phase,
            running: true, guidance: guidance, sessionStartedAt: start, now: start)
        XCTAssertEqual(coach.presentation.sample?.bpm, 160)
        let stale = coach.presentation.visible(at: start.addingTimeInterval(15.1))
        XCTAssertNil(stale.sample)
        XCTAssertEqual(stale.status, .missing)
    }

    func testFutureAndInvalidSamplesAreIgnored() {
        for sample in [HeartRateSample(bpm: .nan, date: start), .init(bpm: 0, date: start),
                       .init(bpm: 160, date: start.addingTimeInterval(4))] {
            XCTAssertFalse(sample.isFresh(at: start))
        }
    }

    func testPhoneOnlyPresentationNeverDisplaysACachedWatchReading() {
        let previous = HeartRatePresentation(sample: .init(bpm: 164, date: start), trendBPM: 164,
            target: HeartRateRange(lower: 153, upper: 171), status: .inTarget)
        let phoneOnly = previous.visible(at: start, allowsLiveSamples: false)
        XCTAssertNil(phoneOnly.sample)
        XCTAssertNil(phoneOnly.trendBPM)
        XCTAssertNil(phoneOnly.target)
        XCTAssertEqual(phoneOnly.status, .waiting)
        XCTAssertEqual(previous.visible(at: start, paused: true, allowsLiveSamples: false).status, .paused)
    }

    func testPauseClearsComparisonAndRejectsPreResumeReadings() {
        var coach = HeartRateCoach()
        let phase = snapshot()
        _ = coach.update(sample: .init(bpm: 180, date: start), snapshot: phase, running: true,
                         guidance: guidance, sessionStartedAt: start, now: start)
        _ = coach.update(snapshot: phase, running: false, guidance: guidance, sessionStartedAt: start,
                         now: start.addingTimeInterval(5))
        XCTAssertEqual(coach.presentation.status, .paused)
        XCTAssertNil(coach.presentation.sample)
        _ = coach.update(sample: .init(bpm: 180, date: start.addingTimeInterval(4)), snapshot: phase,
                         running: true, guidance: guidance, sessionStartedAt: start, now: start.addingTimeInterval(6))
        XCTAssertNil(coach.presentation.sample)
    }

    func testDisplayedRangeAndCueCooldownRequireSustainedFreshSamples() {
        var coach = HeartRateCoach()
        let phase = snapshot()
        var cues: [Int] = []
        for second in stride(from: 0, through: 100, by: 5) {
            let now = start.addingTimeInterval(Double(second))
            if coach.update(sample: .init(bpm: 185, date: now), snapshot: phase, running: true,
                            guidance: guidance, sessionStartedAt: start, now: now) != nil { cues.append(second) }
        }
        XCTAssertEqual(cues, [45, 90])
        XCTAssertEqual(coach.presentation.status, .above)
        _ = coach.update(sample: .init(bpm: 170, date: start.addingTimeInterval(115)), snapshot: phase,
                         running: true, guidance: guidance, sessionStartedAt: start, now: start.addingTimeInterval(115))
        XCTAssertEqual(coach.presentation.status, .inTarget)
        _ = coach.update(sample: .init(bpm: 165, date: start.addingTimeInterval(130)), snapshot: phase,
                         running: true, guidance: guidance, sessionStartedAt: start, now: start.addingTimeInterval(130))
        XCTAssertEqual(coach.presentation.status, .inTarget)
    }

    func testCurrentDisplayedReadingDrivesRecoveryStatusInsteadOfOlderTrend() {
        var coach = HeartRateCoach()
        let phase = snapshot(.recovery, seconds: 100)
        _ = coach.update(sample: .init(bpm: 119, date: start), snapshot: phase, running: true,
            guidance: guidance, sessionStartedAt: start, now: start)
        _ = coach.update(sample: .init(bpm: 100, date: start.addingTimeInterval(1)), snapshot: phase, running: true,
            guidance: guidance, sessionStartedAt: start, now: start.addingTimeInterval(1))
        XCTAssertEqual(coach.presentation.status, .below)
        XCTAssertEqual(HeartRateHalfwayCue.resolve(presentation: coach.presentation, phase: .recovery,
            guidance: guidance, at: start.addingTimeInterval(1)), .up)
        XCTAssertNil(HeartRateStatus.building.coaching)
        XCTAssertNil(HeartRateStatus.easyRecovery.coaching)
        XCTAssertNil(HeartRateStatus.below.coaching)
        XCTAssertEqual(HeartRateStatus.easyRecovery.title, "Below target")
    }

    func testCuesOffAndMissingTargetsRemainUsable() {
        var coach = HeartRateCoach()
        var config = guidance
        config.cuesEnabled = false
        let phase = snapshot()
        for second in stride(from: 0, through: 100, by: 5) {
            let now = start.addingTimeInterval(Double(second))
            XCTAssertNil(coach.update(sample: .init(bpm: 190, date: now), snapshot: phase, running: true,
                                      guidance: config, sessionStartedAt: start, now: now))
        }
        config.maximumBPM = nil
        _ = coach.update(snapshot: phase, running: true, guidance: config, sessionStartedAt: start,
                         now: start.addingTimeInterval(101))
        XCTAssertEqual(coach.presentation.status, .unconfigured)
    }

    func testCommandGateDeduplicatesAndRejectsExpiredWrongSessionAndOldPhase() {
        let session = UUID(), phase = UUID()
        var gate = WorkoutCommandGate()
        let command = RemoteWorkoutCommand(id: UUID(), sessionID: session, control: .skip, phaseID: phase, issuedAt: start)
        XCTAssertTrue(gate.evaluate(command, sessionID: session, phaseID: phase, isActive: true, now: start).execute)
        let duplicate = gate.evaluate(command, sessionID: session, phaseID: UUID(), isActive: true, now: start)
        XCTAssertFalse(duplicate.execute)
        XCTAssertTrue(duplicate.acknowledgement.accepted)
        let expired = RemoteWorkoutCommand(id: UUID(), sessionID: session, control: .pause, phaseID: phase, issuedAt: start)
        XCTAssertFalse(gate.evaluate(expired, sessionID: session, phaseID: phase, isActive: true, now: start.addingTimeInterval(9)).execute)
        XCTAssertFalse(gate.evaluate(.init(id: UUID(), sessionID: UUID(), control: .end, phaseID: phase, issuedAt: start),
            sessionID: session, phaseID: phase, isActive: true, now: start).execute)
        XCTAssertFalse(gate.evaluate(.init(id: UUID(), sessionID: session, control: .skip, phaseID: UUID(), issuedAt: start),
            sessionID: session, phaseID: phase, isActive: true, now: start).execute)
    }

    func testTransportBudgetReservesControlCapacityAndExpiresOldReservations() throws {
        var budget = WorkoutMessageBudget()
        try budget.reserve(60_000, priority: false, at: start)
        XCTAssertThrowsError(try budget.reserve(15_000, priority: false, at: start.addingTimeInterval(1)))
        try budget.reserve(38_000, priority: true, at: start.addingTimeInterval(1))
        XCTAssertThrowsError(try budget.reserve(1, priority: true, at: start.addingTimeInterval(2)))
        XCTAssertThrowsError(try budget.reserve(40_000, priority: false, at: start.addingTimeInterval(10)))
        try budget.reserve(70_000, priority: false, at: start.addingTimeInterval(11))
    }

    @MainActor
    func testMirroredRuntimeUsesSamePhaseIDsRejectsOldStateAndDoesNotRunIndependently() throws {
        let watch = WorkoutRuntime(profile: .norwegian4x4)
        watch.start(at: start)
        watch.update(at: start.addingTimeInterval(10))
        let state = try XCTUnwrap(watch.sessionState(revision: 2, heartRate: .init(), at: start.addingTimeInterval(10)))
        let decoded = try JSONDecoder().decode(WorkoutSessionState.self, from: JSONEncoder().encode(state))
        let phone = WorkoutRuntime(profile: decoded.profile, id: decoded.sessionID, timeline: decoded.timeline, isMirrored: true)
        XCTAssertTrue(phone.applyRemoteState(decoded, at: start.addingTimeInterval(10)))
        XCTAssertEqual(phone.snapshot.phase.id, watch.snapshot.phase.id)
        phone.pause(at: start.addingTimeInterval(11))
        XCTAssertEqual(phone.status, .running)
        phone.update(at: start.addingTimeInterval(100))
        XCTAssertEqual(phone.snapshot.elapsedSeconds, 13)
        XCTAssertEqual(phone.actualActiveSeconds, 10)
        XCTAssertFalse(phone.applyRemoteState(decoded))
        phone.finishMirror(at: start.addingTimeInterval(20))
        let later = try XCTUnwrap(watch.sessionState(revision: 3, heartRate: .init(), at: start.addingTimeInterval(11)))
        XCTAssertFalse(phone.applyRemoteState(later))
        watch.end(at: start.addingTimeInterval(11))
    }

    @MainActor
    func testMirroredPauseAndFinishRoundTripWithoutCreatingASecondWorkout() throws {
        let watch = WorkoutRuntime(profile: .norwegian4x4)
        watch.start(at: start)
        watch.pause(at: start.addingTimeInterval(12.25))
        let state = try XCTUnwrap(watch.sessionState(revision: 1, heartRate: .init(), at: start.addingTimeInterval(20.125)))
        let message = WorkoutSessionMessage(state: state)
        let decoded = try JSONDecoder().decode(WorkoutSessionMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.state?.sentAt, state.sentAt)
        let phone = WorkoutRuntime(profile: state.profile, id: state.sessionID, timeline: state.timeline, isMirrored: true)
        XCTAssertTrue(phone.applyRemoteState(try XCTUnwrap(decoded.state)))
        phone.update(at: start.addingTimeInterval(1_000))
        XCTAssertEqual(phone.snapshot.elapsedSeconds, 12.25)
        watch.end(at: start.addingTimeInterval(30))
        let record = try XCTUnwrap(watch.finishedRecord())
        phone.finishMirror(at: record.endedAt, record: record)
        XCTAssertEqual(phone.finishedRecord()?.id, record.id)
        XCTAssertEqual(phone.actualActiveSeconds, record.actualActiveSeconds)
    }

    @MainActor
    func testMaximumProfilePayloadFitsHealthKitBudget() throws {
        var profile = WorkoutProfile.norwegian4x4
        profile.repeatCount = 20
        profile.cooldownSeconds = 300
        profile.heartRateGuidance = guidance
        let runtime = WorkoutRuntime(profile: profile)
        runtime.start(at: start)
        let state = try XCTUnwrap(runtime.sessionState(revision: 1, heartRate: .init(), at: start))
        let size = try JSONEncoder().encode(WorkoutSessionMessage(state: state)).count
        XCTAssertLessThan(size, 9_000)
        runtime.end(at: start)
    }
}
