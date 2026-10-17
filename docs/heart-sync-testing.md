# Heart Sync Preview — 1.2 (6)

This preview lives on `heart-sync`, with a dedicated internal TestFlight group named **Heart Sync Testing**. It includes an embedded Apple Watch app. Install build 6 on both devices; this is a testing build, not an App Store submission.

## Start here

1. Open **Settings → Heart-rate targets**. Enter and save your own maximum BPM and identify its source, or use custom BPM ranges in the workout editor. No maximum is guessed from Apple Health. Personal maximum changes take effect on the next workout.
2. Open **Settings → Heart Sync Preview → Add 6½-minute Heart Sync Check**. This adds an editable profile: 30-second warmup, two 2-minute work intervals, 90-second recovery, and 30-second cooldown. The button never starts exercise automatically.
3. Edit the profile if needed, then tap **Start with Apple Watch**. Open VO2Cue on the paired Watch and allow workout and heart-rate access when asked. A slow permission response can expire the start request; simply start again. A failed phone acknowledgement can mean Watch already started, so check Watch before retrying.
4. Alternatively, start a saved profile on Watch and open the iPhone app to view the same workout. Normal **Start workout** remains a phone timer for profiles without guidance; an explicit Watch start is also available. **Use phone timer without heart rate** retains timing without a sensor.

Default targets are 85–95% of the user-confirmed maximum during work and 60–70% during active recovery, with editable per-profile BPM overrides. These are training targets from [NTNU CERG](https://www.ntnu.edu/cerg/advice), not medical thresholds. Existing profiles remain guidance-off until enabled. Warmup and cooldown show BPM without deviation coaching. Existing custom phase labels remain intact.

## Physical-device checks

- Compare phase, round, remaining time, raw BPM, and the target on both devices. The phone target meter follows the raw number; the status uses the Watch's recent ten-second trend and a 3 BPM hysteresis margin.
- Start from each device. Pause, resume, skip and end from each device. Phone commands wait for Watch acknowledgement, are deduplicated, expire after eight seconds, and cannot skip a different phase than the one selected. The phone never starts a competing interval engine for a Watch workout.
- Work below target shows **Building** during the first 90 seconds. Recovery above target shows **Settling** during the first 60 seconds. Above-target work remains visible; below-target recovery says **Keep recovery easy**. These transition windows are product parameters for evaluation.
- Coaching requires ten seconds of sustained deviation and a fresh new sample, with a 45-second cooldown. Interval cues take priority. Pause and stale data suppress coaching; there is no recurring in-target cue. Heart-rate cues obey the per-profile toggle; speech also requires Spoken cues.
- Lock iPhone, lower your Watch wrist and background the phone app. Enable Live Activities for VO2Cue before locked-phone testing. Check the phase timer on the Live Activity and reopen the app to compare current state. The Live Activity displays the interval timer, not a continuously refreshed heart-rate readout.
- Move the phone out of range and return. Watch should continue independently. Phone controls become unavailable during a stale connection. On reconnection, the full current state replaces the phone projection. Phone projection freezes after three seconds without an update rather than executing independent phase changes.
- Remove the Watch or otherwise create a sensor gap. After 15 seconds without a fresh reading, BPM and comparison disappear; the timer continues. Waiting, paused and missing readings are distinct. No cached Apple Health reading is used as current HR. Empty data does not establish denied read permission.
- Test swimming and vigorous wrist movement. Do not expect a fixed sampling cadence or guaranteed subsecond radio delivery. Sync diagnostics show measurement age, update age and estimated delivery delay using device clocks; they do not measure sensor latency.
- Finish normally and end early. Confirm one local history entry per session ID, correct active/paused/skipped time, and a single Apple Health workout saved by Watch. The iPhone mirror never saves another Health workout. Check completion after disconnect/reconnect as well.
- If Watch restarts during an active session, HealthKit recovery restores the saved interval state and remirrors it with a newer revision. Check recovery timing on real devices; the checkpoint is refreshed at transitions and about every ten seconds.

## Implementation and privacy

Watch owns the `HKWorkoutSession`, `HKLiveWorkoutBuilder`, interval runtime and coaching classifier. iPhone registers `workoutSessionMirroringStartHandler` at initialization. An expiring acknowledged WatchConnectivity message supplies the exact profile after `startWatchApp` wakes Watch; workout telemetry and controls use HealthKit's bidirectional mirrored-session channel. Profiles, confirmed maximum settings, purchase access and completed records retain durable WatchConnectivity delivery.

Live packets preserve fractional-second sample timestamps, session IDs, phase IDs and ordered revisions. Sends have a three-second completion timeout, coalesce routine state updates, and reserve bandwidth for acknowledgements and final state within HealthKit's 100 KB/10-second limit. Completed records prevent older packets from reopening a workout. Timers, settings and existing saved records remain backward compatible.

Health information and diagnostics remain on the paired devices. Heart-rate samples are used transiently for live coaching; they are not added to VO2Cue's JSON history or sent to the developer. The short active-session recovery checkpoint can contain the latest reading until it is overwritten at the next workout. TestFlight has no simulated heart-rate source. Debug-only, clearly labeled UI fixtures are compiled out of Release builds.

This preview does not add a time-in-zone score or post-workout HR chart. Its first physical-device milestone is establishing real sensor behavior, responsive controls, and reconnection before adding those summaries.

## Automated evidence

- iOS 17.5: 65 unit tests passed, including 16 heart-rate/protocol tests and the existing StoreKit tests.
- iOS 26.3: work/recovery, missing and paused HR presentations passed; existing workout controls/history passed. Settings/profile target editing, widget-start preservation, and the largest accessibility text size passed in targeted reruns. Accessibility controls use labeled icons at the largest sizes so the scrollable heart-rate card remains reachable.
- Signed Release archive: iPhone app, embedded Watch app and widget extension built successfully as 1.2 (6). Export/upload succeeded on October 17, 2026. App Store Connect verified version 1.2 (6) as VALID and IN_BETA_TESTING, assigned to Heart Sync Testing with the existing internal tester. English What to Test notes were read back and matched Config/TestFlight-HeartSync.txt; exempt encryption was confirmed. No App Store release or external Beta App Review was submitted.
- UI captures and test result bundles are saved locally under `output/heart-sync-validation` and `build`; simulator screenshots use explicitly simulated Debug fixtures and do not establish physical HR or radio behavior.

Apple references: [multidevice workout walkthrough](https://developer.apple.com/videos/play/wwdc2023/10023/) and [mirrored-session reconnection](https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:diddisconnectfromremotedevicewitherror:)).
