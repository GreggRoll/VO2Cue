# Changelog

All notable VO2Cue changes are documented here.

## Unreleased — Consistency and progress

### Added

- Editable weekly active-minute goals and an eight-week Progress chart, with partial sessions included.
- Small and medium Home Screen widgets show weekly goal progress and completion; the medium widget starts the most recently used phone workout.
- Previewable Norwegian 4×4, Short Intervals, and Easy 20 templates that become editable workout profiles.
- iPhone and Watch summaries with actual training time, phase totals, and skipped-phase counts.
- Optional local effort ratings and workout notes, editable from Progress.
- Optional weekday reminders at a chosen local time, with permission requested only when enabled and navigation to Workouts on tap.

### Changed

- Replaced the History tab with Progress while preserving history and deletion controls.
- Kept legacy workout entries readable and labeled their duration as recorded time; excluded them from new goals and charts.
- Used Hard for newly created interval profiles and preserved existing saved cue labels.
- Removed the follow-up roadmap from the release scope.

### Fixed

- Separated actual training time from timeline position so skipping a phase does not add training minutes.
- Capped delayed natural completion at its scheduled finish and retained phase-level time through pause/resume and early endings.
- Read stored and launch-supplied Health saving preferences consistently as booleans.

### Validation

- Passed all 45 unit tests, including existing purchase tests, on iOS 17.5.
- Verified all ten UI scenarios on iOS 26.3 across the full run and corrected reruns, including largest accessibility text and persisted workout notes.
- Passed unsigned iPhone/Watch Release builds. Physical-device and TestFlight checks remain documented in `docs/next-release-validation.md`.

## 1.0 (2) — 2026-08-28

### Fixed

- Made the Health access action show request progress and a clear success, denial, unavailable, or failure result instead of appearing unresponsive after a previous decision.
- Restored the saved Health authorization state when the app launches or returns from Settings.
- Added a direct route to app Settings when Health workout access has been denied.
- Made custom workout profile sync wait for WatchConnectivity activation instead of dropping early updates.
- Added automatic retry when Apple Watch pairing, installation, or reachability changes.
- Added immediate acknowledged profile delivery when Apple Watch is reachable while retaining durable application-context delivery for disconnected use.
- Preserved profiles received before the Apple Watch model finishes installing its handler.

### Changed

- Added Apple Watch sync status beneath the workout list.
- Centralized and tested the shared WatchConnectivity payload format.
- Bumped the iPhone and Apple Watch build numbers to 2.

### Validation

- Verified the Health authorization sheet on iOS Simulator.
- Passed all nine unit tests and two UI integration tests.
- Archived the iPhone and embedded Apple Watch apps with App Store distribution signing.
- Uploaded version 1.0, build 2 to TestFlight; App Store Connect reported `VALID`.

## 1.0 (1) — 2026-08-24

### Added

- Initial TestFlight release of the SwiftUI iPhone and independent Apple Watch apps.
- Custom 4×4 workout profiles, eyes-free cues, local workout history, and HealthKit workout saving.
- Apple Watch workout controls, haptics, live heart rate, and direct device-to-device profile and history transfer.
