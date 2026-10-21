# VO2Cue: phase-aware heart rate

Design proposal only. Sample data is simulated; the app source is unchanged.

## Recommended layout

Keep the existing hierarchy of phase, round, countdown and next interval. Insert a heart-rate card beneath the timer on iPhone. On Watch, promote the existing BPM label to a larger reading with a short status and numeric target. Keep Watch controls on the second page. Preserve custom hard and recovery labels.

The interactive proposal includes a timer-first recommendation and a heart-rate-first alternative. Both share phase and sample readings. Settings demonstrates maximum heart rate, derived targets and cue preference.

## Target setup

Add Heart-rate guidance to the workout profile. Guidance is optional; timing still works without a sensor or configured targets. Collect a user-confirmed maximum heart rate, with explicit source (measured, entered, or estimated), and allow custom hard and recovery BPM ranges. Keep maximum heart rate in personal settings, with profile-specific target overrides. Do not silently treat Apple Health's highest recorded sample as a true maximum.

Suggested Norwegian 4×4 defaults: hard 85–95% of maximum; active recovery 60–70%. Source: NTNU CERG https://www.ntnu.edu/cerg/advice . Some NTNU instructions describe recovery as approximately 70%; these are editable training targets rather than medical thresholds. The example uses 180 BPM maximum: 153–171 BPM hard, 108–126 BPM recovery. This is example data, not a personal recommendation.

## Feedback behavior

Display current fresh BPM, the phase's target range, and Below target / In target / Above target. Include arrows and text, so state never relies solely on color. Use training-target language rather than safe/unsafe labels. Below recovery target should say Keep recovery easy; do not nudge users to push harder during recovery merely to enter the band.

Account for the normal heart-rate response after phase changes. Show Building during early work and Settling during early recovery. Initial product proposal: suppress low-work coaching for the first 90 seconds, and high-recovery cues for 60 seconds, while keeping the live reading and numerical target visible. Continue displaying above-target work readings immediately. These timing choices require device and workout evaluation; they are product decisions, not physiological cutoffs. NTNU notes that reaching work intensity can take 1–2 minutes.

Use a shared classifier with a short rolling window of fresh samples, sustained deviation before a cue, and a small hysteresis margin before changing status. Example starting parameters for validation: 10-second smoothing, 10 seconds sustained outside the range, 3 BPM hysteresis, and a 45-second cue cooldown. Never smooth away or reclassify the displayed raw number without making the relationship understandable; UI may label the status as based on a recent trend. Prototype examples represent settled sample states and do not implement these algorithms.

Haptic and optional spoken heart-rate cues supplement existing interval cues. Interval transitions take priority, and pause suppresses coaching. Use distinguishable short haptic patterns for above/below target and a brief optional voice cue; no repeating in-target cue. Provide a per-workout toggle. Do not cue from old data.

## Missing data and privacy

Use timestamped samples. If no new sample arrives within a validated freshness period (initial proposal: 15 seconds), clear the comparison and show No fresh reading, retaining the timer. Distinguish waiting for the first sample, lost signal and disconnected Watch when evidence allows. HealthKit read denial cannot reliably be inferred from an empty query. Do not present a cached BPM as live or infer health status from a dropout. Test swimming and wrist-motion gaps.

The iPhone has no built-in HR sensor. It needs fresh readings from a paired Watch or a separately supported sensor. Do not use an old Apple Health sample as current heart rate. Only show Live while the actual stream is fresh.

## Code integration

The current WatchHealthSession already collects HKLiveWorkoutBuilder heart rate, but does not expose its sample timestamp. WatchRuntimeView shows BPM beneath progress. WorkoutRuntimeView on iPhone currently has no HR data input. Existing WatchConnectivityPayload supports profiles, purchase access and completed records, not live heart rate or mirrored session state.

For a live iPhone companion, design one authoritative workout session on Watch with a supported mirroring/session-data channel; synchronize session ID, profile, phase/round, pause and timing as well as timestamped BPM. Verify platform availability for iOS 17/watchOS 10 and independent Watch operation before selecting the transport. Avoid simultaneous independent timers and duplicate Health workout saves. If using WatchConnectivity for supplementary delivery, treat delivery as best effort and preserve freshness semantics. Background and locked-screen reliability need real-device validation.

Add optional backward-compatible guidance configuration to shared models and profile sync. Implement target calculation/classification in shared code, then inject the same presentation state into both screens. Keep per-sample observation local to the HR component. Preserve default timer behavior, warmup/cooldown, missing-config fallback, Dynamic Type, VoiceOver, reduced motion, and local-only health data handling. Warmup/cooldown can show BPM without deviation coaching in the first release.

Verification before shipping: target rounding and overrides; phase changes and custom labels; late readings from previous sessions; stale/out-of-order samples; hysteresis and cue cooldown; paused/resumed sessions; denied/missing Health data; reconnection; Watch standalone use; phone lock/background; VoiceOver and larger text. A useful later summary is time in each phase's target, explicitly excluding missing readings and labeling transition time.
