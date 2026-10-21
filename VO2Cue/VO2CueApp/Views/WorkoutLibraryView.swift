import SwiftUI

struct WorkoutLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(WorkoutTemplate.allCases) { template in
                NavigationLink {
                    TemplatePreview(template: template) { profile in
                        model.upsert(profile)
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.title).font(.headline)
                        Text("\(template.makeProfile().estimatedDuration / 60) minutes")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("workoutTemplate_\(template.id)")
            }
            .navigationTitle("Workout library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

private struct TemplatePreview: View {
    let template: WorkoutTemplate
    let add: (WorkoutProfile) -> Void
    private let previewProfile: WorkoutProfile
    private let timeline: WorkoutTimeline

    init(template: WorkoutTemplate, add: @escaping (WorkoutProfile) -> Void) {
        self.template = template
        self.add = add
        let profile = template.makeProfile()
        previewProfile = profile
        timeline = WorkoutTimeline(profile: profile)
    }

    var body: some View {
        List {
            Section {
                Text(template.explanation)
                Label("\(previewProfile.estimatedDuration / 60) minutes", systemImage: "clock")
                Text("Add this template, then edit its activity, intervals, and cues to suit you.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Session preview") {
                ForEach(timeline.phases) { phase in
                    LabeledContent {
                        Text(phase.durationSeconds.timerText).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(phase.displayTitle)
                            if let round = phase.roundDescription {
                                Text(round).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button("Add to my workouts", systemImage: "plus") { add(template.makeProfile()) }
                    .accessibilityIdentifier("addWorkoutTemplate")
            }
        }
        .navigationTitle(template.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
