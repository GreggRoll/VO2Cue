import XCTest
import UserNotifications
@testable import VO2Cue

@MainActor
private final class FakeWorkoutNotifications: WorkoutNotificationClient {
    var status: UNAuthorizationStatus = .notDetermined
    var allowsPermission = true
    var permissionRequests = 0
    var pending: [String: UNNotificationRequest] = [:]
    var failNextAdd = false

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        status = allowsPermission ? .authorized : .denied
        return allowsPermission
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func add(_ request: UNNotificationRequest) async throws {
        if failNextAdd {
            failNextAdd = false
            throw NSError(domain: "ReminderTest", code: 1)
        }
        pending[request.identifier] = request
    }
    func remove(_ identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) } }
}

@MainActor
final class WorkoutReminderTests: XCTestCase {
    func testDefaultsDoNotAskPermissionAndEnablingSchedulesLocalCalendarRequests() async throws {
        let client = FakeWorkoutNotifications()
        var saved = WorkoutReminderSchedule()
        let store = WorkoutReminderStore(schedule: saved, client: client, save: { saved = $0 })
        await store.refreshAuthorization()
        XCTAssertFalse(store.schedule.enabled)
        XCTAssertEqual(client.permissionRequests, 0)
        var draft = store.schedule
        draft.enabled = true
        draft.weekdays = [2, 6]
        draft.hour = 7
        draft.minute = 30
        let success = await store.update(draft)
        XCTAssertTrue(success)
        XCTAssertEqual(client.permissionRequests, 1)
        XCTAssertEqual(saved, draft)
        XCTAssertEqual(client.pending.count, 2)
        for request in client.pending.values {
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertTrue(trigger.repeats)
            XCTAssertEqual(trigger.dateComponents.hour, 7)
            XCTAssertEqual(trigger.dateComponents.minute, 30)
            XCTAssertNil(trigger.dateComponents.timeZone)
            XCTAssertTrue(WorkoutReminderStore.isWorkoutReminder(request))
        }
        let decoded = try JSONDecoder.vo2Cue.decode(WorkoutReminderSchedule.self, from: JSONEncoder.vo2Cue.encode(saved))
        XCTAssertEqual(decoded, draft)
    }

    func testDeniedPermissionLeavesRemindersOff() async {
        let client = FakeWorkoutNotifications()
        client.allowsPermission = false
        let store = WorkoutReminderStore(schedule: WorkoutReminderSchedule(), client: client, save: { _ in })
        var draft = store.schedule
        draft.enabled = true
        let success = await store.update(draft)
        XCTAssertFalse(success)
        XCTAssertFalse(store.schedule.enabled)
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertEqual(store.authorizationStatus, .denied)
        XCTAssertNotNil(store.errorMessage)
    }

    func testDisablingRemovesOnlyVO2CueRemindersWithoutAskingPermission() async {
        let client = FakeWorkoutNotifications()
        client.status = .denied
        var schedule = WorkoutReminderSchedule()
        schedule.enabled = true
        for request in schedule.requests { client.pending[request.identifier] = request }
        let other = UNNotificationRequest(identifier: "unrelated", content: UNMutableNotificationContent(), trigger: nil)
        client.pending[other.identifier] = other
        let store = WorkoutReminderStore(schedule: schedule, client: client, save: { _ in })
        schedule.enabled = false
        let success = await store.update(schedule)
        XCTAssertTrue(success)
        XCTAssertEqual(Set(client.pending.keys), ["unrelated"])
        XCTAssertEqual(client.permissionRequests, 0)
        XCTAssertFalse(WorkoutReminderStore.isWorkoutReminder(other))
    }

    func testScheduleReplacementAndAddFailureRestorePreviousRequests() async {
        let client = FakeWorkoutNotifications()
        client.status = .authorized
        var original = WorkoutReminderSchedule()
        original.enabled = true
        original.weekdays = [2]
        for request in original.requests { client.pending[request.identifier] = request }
        let store = WorkoutReminderStore(schedule: original, client: client, save: { _ in })
        var desired = original
        desired.weekdays = [3, 5]
        client.failNextAdd = true
        let failed = await store.update(desired)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.schedule, original)
        XCTAssertEqual(Set(client.pending.keys), Set(original.requests.map(\.identifier)))
        let success = await store.update(desired)
        XCTAssertTrue(success)
        XCTAssertEqual(Set(client.pending.keys), Set(desired.requests.map(\.identifier)))
    }

    func testPersistenceFailureRestoresScheduleAndRequests() async {
        let client = FakeWorkoutNotifications()
        client.status = .authorized
        var original = WorkoutReminderSchedule()
        original.enabled = true
        original.weekdays = [2]
        for request in original.requests { client.pending[request.identifier] = request }
        let store = WorkoutReminderStore(schedule: original, client: client,
                                         save: { _ in throw NSError(domain: "PersistenceTest", code: 1) })
        var desired = original
        desired.weekdays = [5]
        let success = await store.update(desired)
        XCTAssertFalse(success)
        XCTAssertEqual(store.schedule, original)
        XCTAssertEqual(Set(client.pending.keys), Set(original.requests.map(\.identifier)))
    }

    func testNoWeekdayIsRejectedBeforePermissionPrompt() async {
        let client = FakeWorkoutNotifications()
        let store = WorkoutReminderStore(schedule: WorkoutReminderSchedule(), client: client, save: { _ in })
        var draft = store.schedule
        draft.enabled = true
        draft.weekdays = []
        let success = await store.update(draft)
        XCTAssertFalse(success)
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testOnlyWorkoutReminderTapRequestsWorkoutsNavigation() {
        let store = WorkoutReminderStore(schedule: WorkoutReminderSchedule(), client: FakeWorkoutNotifications(), save: { _ in })
        let unrelated = UNNotificationRequest(identifier: "unrelated", content: UNMutableNotificationContent(), trigger: nil)
        store.handleReminder(unrelated)
        XCTAssertFalse(store.openWorkoutsRequested)
        var schedule = WorkoutReminderSchedule()
        schedule.enabled = true
        store.handleReminder(schedule.requests[0])
        XCTAssertTrue(store.openWorkoutsRequested)
    }
}

@MainActor
final class TrainingProgressStoreTests: XCTestCase {
    func testGoalAndNotesSaveAndIncomingRecordsDoNotOverwriteAnnotations() {
        var saved = VO2Cue.TrainingPreferences()
        let store = TrainingProgressStore(preferences: saved, save: { saved = $0 })
        let id = UUID()
        store.setGoal(95)
        store.setAnnotation(VO2Cue.WorkoutAnnotation(effort: 7, note: "Treadmill"), for: id)
        let incoming = VO2Cue.WorkoutRecord(id: id, profileID: UUID(), profileName: "Watch workout", activity: .other,
                                            startedAt: Date(), endedAt: Date(), activeSeconds: 60, completed: true,
                                            actualActiveSeconds: 60)
        store.retainAnnotations(for: [incoming, incoming])
        XCTAssertEqual(store.annotation(for: id).note, "Treadmill")
        XCTAssertEqual(saved.weeklyGoalMinutes, 95)
        let restored = TrainingProgressStore(preferences: saved, save: { _ in })
        XCTAssertEqual(restored.annotation(for: id).effort, 7)
        restored.retainAnnotations(for: [])
        XCTAssertEqual(restored.annotation(for: id), VO2Cue.WorkoutAnnotation())
    }

    func testFailedSaveDoesNotClaimGoalOrNoteWasPersisted() {
        let store = TrainingProgressStore(preferences: VO2Cue.TrainingPreferences(),
                                          save: { _ in throw NSError(domain: "PersistenceTest", code: 1) })
        store.setGoal(95)
        XCTAssertEqual(store.weeklyGoalMinutes, 60)
        XCTAssertNotNil(store.errorMessage)
    }
}
