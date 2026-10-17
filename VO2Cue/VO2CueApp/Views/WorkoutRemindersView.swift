import SwiftUI
import UIKit

struct WorkoutRemindersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let store: WorkoutReminderStore
    @State private var draft: WorkoutReminderSchedule
    @State private var time: Date

    init(store: WorkoutReminderStore) {
        self.store = store
        let schedule = store.schedule
        // A local editing draft; permissions are requested only on Save when enabled.
        _draft = State(initialValue: schedule)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: schedule.hour, minute: schedule.minute)) ?? Date())
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Workout reminders", isOn: $draft.enabled)
                    .accessibilityIdentifier("workoutRemindersEnabled")
            } footer: {
                Text("Optional reminders to choose a workout. They follow your local time and never start a session automatically.")
            }
            if draft.enabled {
                Section("Days") {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        Button {
                            if draft.weekdays.contains(weekday) { draft.weekdays.remove(weekday) }
                            else { draft.weekdays.insert(weekday) }
                        } label: {
                            HStack {
                                Text(Calendar.current.weekdaySymbols[weekday - 1])
                                Spacer()
                                Image(systemName: draft.weekdays.contains(weekday) ? "checkmark.circle.fill" : "circle")
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityValue(draft.weekdays.contains(weekday) ? "Selected" : "Not selected")
                        .accessibilityIdentifier("reminderWeekday\(weekday)")
                    }
                }
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
            if store.authorizationStatus == .denied {
                Section {
                    Text("Notifications are off in system Settings.")
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .disabled(store.isSaving)
        .navigationTitle("Workout reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(store.isSaving ? "Saving…" : "Save") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    draft.hour = components.hour ?? 18
                    draft.minute = components.minute ?? 0
                    Task { if await store.update(draft) { dismiss() } }
                }
                .disabled(store.isSaving || (draft.enabled && draft.weekdays.isEmpty))
                .accessibilityIdentifier("saveWorkoutReminders")
            }
        }
        .task { await store.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshAuthorization() } }
        }
    }
}
