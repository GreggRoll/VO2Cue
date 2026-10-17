import Foundation
import Observation
import UserNotifications

struct WorkoutReminderSchedule: Codable, Equatable {
    var enabled = false
    // Calendar weekday values: Sunday = 1 ... Saturday = 7.
    var weekdays: Set<Int> = [2, 5]
    var hour = 18
    var minute = 0

    var sanitized: Self {
        Self(enabled: enabled, weekdays: weekdays.intersection(1...7),
             hour: min(23, max(0, hour)), minute: min(59, max(0, minute)))
    }

    var requests: [UNNotificationRequest] {
        guard enabled else { return [] }
        return weekdays.sorted().map { weekday in
            let content = UNMutableNotificationContent()
            content.title = "Time for your cardio?"
            content.body = "Choose a session that fits your day. Every active minute counts."
            content.sound = .default
            content.userInfo = ["destination": "workouts"]
            // No time zone: the calendar trigger follows the device's local time.
            let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
            return UNNotificationRequest(identifier: "vo2cue.workout-reminder.\(weekday)", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        }
    }
}

@MainActor
protocol WorkoutNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ identifiers: [String])
}

@MainActor
private struct SystemWorkoutNotifications: WorkoutNotificationClient {
    let center = UNUserNotificationCenter.current()
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}

@MainActor
@Observable
final class WorkoutReminderStore: NSObject, UNUserNotificationCenterDelegate {
    private(set) var schedule: WorkoutReminderSchedule
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var errorMessage: String?
    private(set) var isSaving = false
    var openWorkoutsRequested = false
    @ObservationIgnored private let client: any WorkoutNotificationClient
    @ObservationIgnored private let save: (WorkoutReminderSchedule) throws -> Void
    private static let prefix = "vo2cue.workout-reminder."

    init(schedule: WorkoutReminderSchedule? = nil, client: (any WorkoutNotificationClient)? = nil,
         save: ((WorkoutReminderSchedule) throws -> Void)? = nil) {
        self.schedule = (schedule ?? Persistence.load(WorkoutReminderSchedule.self, fileName: "workout-reminders.json") ?? WorkoutReminderSchedule()).sanitized
        self.client = client ?? SystemWorkoutNotifications()
        self.save = save ?? { try Persistence.save($0, fileName: "workout-reminders.json") }
        super.init()
    }

    func installNotificationHandler() {
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshAuthorization() async {
        authorizationStatus = await client.authorizationStatus()
    }

    @discardableResult
    func update(_ draft: WorkoutReminderSchedule) async -> Bool {
        guard !isSaving else { return false }
        let desired = draft.sanitized
        guard !desired.enabled || !desired.weekdays.isEmpty else {
            errorMessage = "Choose at least one reminder day."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        await refreshAuthorization()
        do {
            if desired.enabled {
                if authorizationStatus == .notDetermined {
                    _ = try await client.requestAuthorization()
                    await refreshAuthorization()
                }
                guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
                    errorMessage = "Notifications are off. Allow notifications for VO2Cue in Settings to enable reminders."
                    return false
                }
            }

            let previous = await client.pendingRequests().filter { $0.identifier.hasPrefix(Self.prefix) }
            client.remove(previous.map(\.identifier))
            do {
                for request in desired.requests { try await client.add(request) }
                try save(desired)
                schedule = desired
                return true
            } catch {
                client.remove(desired.requests.map(\.identifier))
                for request in previous { try? await client.add(request) }
                throw error
            }
        } catch {
            errorMessage = "Couldn’t save reminders. Please try again."
            return false
        }
    }

    static func isWorkoutReminder(_ request: UNNotificationRequest) -> Bool {
        request.identifier.hasPrefix(prefix) && request.content.userInfo["destination"] as? String == "workouts"
    }

    func handleReminder(_ request: UNNotificationRequest) {
        if Self.isWorkoutReminder(request) { openWorkoutsRequested = true }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            handleReminder(response.notification.request)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Foreground reminders stay quiet during a session.
        completionHandler([])
    }
}
