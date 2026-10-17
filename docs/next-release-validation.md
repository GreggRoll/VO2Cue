# Consistency and progress release validation

## Behavior and migration

The Workouts screen includes a weekly goal and a previewable three-template library. Progress replaces the History tab while retaining history and deletion controls. iPhone summaries include optional effort ratings (1–10) and notes (up to 2,000 characters); Watch summaries show actual time, phase totals, and skipped phases.

The runtime maintains timeline position for cues/audio separately from actual time traversed in each phase. Pause, skip, and end settle current elapsed time before applying their control action. A delayed natural completion caps training time and its end date at the scheduled finish rather than counting excess time after the finish.

New `WorkoutRecord` fields `actualActiveSeconds` and `phaseResults` are optional for compatibility. Older JSON and Watch payloads continue to decode, and older app versions can ignore the added JSON fields. Existing custom profiles and cue labels remain untouched. New profiles use Hard (or Steady for Easy 20).

Legacy entries display recorded time and do not contribute to weekly goals or charts. New partial sessions do contribute. Sessions are attributed to the calendar week containing their start, in the current local timezone. The chart includes the current week and seven preceding weeks, including zero-minute weeks. The goal starts at 60 minutes and is user editable; it is not a health recommendation.

Notes are saved separately from Watch records and keyed by record ID. Watch transfer deduplication and progress aggregation use record IDs. Deleting history removes annotations and recalculates progress. Apple Health workouts are not deleted.

Reminders are disabled by default. Enabling and saving requests notification permission only if it has not already been decided. Selected weekdays and local time create repeating calendar notifications; no fixed timezone is attached. Changing the schedule replaces VO2Cue's pending reminder requests; disabling removes them without requiring permission. Failed scheduling or persistence attempts restore the prior requests. Tapping a reminder selects Workouts while preserving onboarding, purchase gates, and any active session. Foreground reminders do not interrupt workouts.

The Weekly goal Home Screen widget supports small and medium sizes. Both show the saved active-minute goal and completion ring; the medium adds the most recently started phone profile and a Start workout link. The link opens the app, verifies purchase access, and starts the profile after onboarding. Existing running/paused workouts are preserved. The app publishes a minimal snapshot through `group.com.gregadams.vo2cue.shared` after profile, goal, or history changes. The timeline includes a new-week entry, calculated from session start dates in the local calendar, so last week's completion resets even without opening the app.

## Automated checks

- Runtime: actual versus timeline seconds, running/paused skips, fractional updates, delayed phase crossings, early end, natural completion, clock reversal, and single finish delivery.
- Templates: exact durations, phase ordering, recovery only between rounds, and independently editable profile IDs.
- Migration/progress: legacy JSON and Watch payload decoding, richer payload round trips, duplicate IDs, partial sessions, empty weeks, week boundaries, differing first weekdays, spring daylight saving, annotation persistence/deletion, and failed persistence.
- Reminders: opt-in authorization, permission denial, calendar components, replacement/disabling, unrelated-notification preservation, scheduling/persistence rollback, and tap routing.
- Existing purchase, review policy, cue schedule, timeline, and onboarding regression tests.
- UI flows: goal editing and relaunch, template preview/add, runtime controls with accurate skipped time, workout notes and relaunch, Progress navigation, disabled reminder editing, and the largest accessibility text setting.

Use the VO2Cue Purchases scheme with the iOS 17.5 simulator for the complete unit suite, including existing StoreKit tests. Use the normal VO2Cue scheme on iOS 26.3 for UI tests. The app continues to target iOS 17+ and watchOS 10+.

## Verification results

- All 45 unit tests passed on iOS 17.5, including the five existing StoreKit tests.
- All 10 distinct UI scenarios passed on iOS 26.3 across the full suite and corrected reruns. The full run passed nine cases; its older profile-creation test assumed a newly saved row was visible. After adding scrolling, the final focused run passed profile creation, largest accessibility text, template/reflection persistence, and runtime controls/history (four tests, zero failures).
- Visually reviewed the template preview, normal and largest-text Progress layouts, reflection editor, and saved workout detail.
- Unsigned Release builds passed for the iPhone app, embedded Watch app, and Live Activity extension.
- Widgets: Debug simulator builds passed, including an ad hoc signed build with App Group entitlements. Nine focused unit tests passed on iOS 26.3 (four new widget tests and five existing training-progress tests). Three focused UI tests passed for cold Progress launch, purchase gating, workout start, preserving a paused workout after a second widget URL, and goal persistence. Confirmed a goal edit publishes the updated value to the shared container. Visually reviewed small and medium widgets on the Home Screen.
- `git diff --check` passed. Existing local work was preserved.

## Required physical-device validation before production

Simulator checks cannot establish real-device locked-screen audio or Watch delivery reliability. Perform these checks in TestFlight before production release:

- Lock an iPhone during warmup and listen through countdowns, transitions, halfway cues, and completion; repeat with voice only and tones only.
- Repeat pause/resume, skip, early end, music mixing, headphones disconnecting, calls, and Live Activity behavior. Verify actual duration and summary breakdowns afterward.
- Complete and end sessions early on an independently operating Watch. Pause and skip phases; confirm summaries and actual minutes. Reconnect after offline use and verify transfer appears once on iPhone and preserves notes.
- Tap a reminder with the app closed, backgrounded, foregrounded, locked for purchases, and running a session. Verify it opens Workouts without creating a runtime or bypassing access.
- The shared group is registered and associated with both iPhone and widget bundle IDs, and fresh App Store distribution profiles are installed. Add both widget sizes on a physical device; check phone/Watch completions, partial sessions, history deletion, goal edits, profile rename/deletion, week rollover, timezone changes, and medium Start workout behavior through onboarding/purchase gates and an existing workout.
- Enable, change, and disable reminders. Deny permission, re-enable in system Settings, cross a timezone change, and verify local-time behavior.
- Check VoiceOver descriptions and chart exploration, largest accessibility text sizes, reduced motion, and both purchase access types.
- Review the new library guidance and use the release with a small opt-in group for two weeks. Gather voluntary feedback; add no analytics.

Version 1.1 (5) was archived with valid distribution signatures and uploaded to App Store Connect on October 12, 2026. The signed iPhone app and widget extension both contain `group.com.gregadams.vo2cue.shared`; the archive declares no non-exempt encryption. All nine focused widget/progress tests and the unsigned Release preflight passed. Apple processed the build as `VALID`; internal TestFlight state is `IN_BETA_TESTING`, and the existing Alpha group has access. The English What to Test notes were saved and verified. Production release still requires the physical-device checks above.

The TestFlight product-ID mismatch was corrected in App Store Connect on October 12, 2026. Created `com.gregadams.vo2cue.lifetime` (non-consumable, Apple ID `6822101878`) and `com.gregadams.vo2cue.monthly` (one-month auto-renewable subscription, Apple ID `6822101918`). Both products are `READY_TO_SUBMIT`, with English metadata, completed paywall review screenshots, and availability in 175 territories. Verified US pricing is $19.99 once and $1.99/month; the subscription has all 175 localized price points. The earlier `vo2cuepro` consumable and `vo2cuepromonthly` subscription remain untouched and are not requested by the app.

Allow up to one hour for the corrected catalog to propagate to Apple's sandbox, then use **Try again** on the existing TestFlight paywall. A new binary is not required for this catalog correction. Actual TestFlight price loading, checkout, and restoration remain physical-device validation steps; API verification does not establish successful StoreKit delivery. Submit both new products with the first app version offering them before production release.
