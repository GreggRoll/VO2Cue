# VO2Cue: 4x4 Timer

VO2Cue is an open-source, VO2-focused 4x4 interval coach for Apple Watch, swimming, and eyes-free training. Contributions are welcome!

V1.0 is implemented and running in TestFlight for iOS 17+ and watchOS 10+. The latest release is version 1.0, build 2. Read the [changelog](CHANGELOG.md) and [VO2Cue Privacy Policy](https://greggroll.github.io/VO2Cue/privacy).

Explore the [app demo and quick-start guide](https://greggroll.github.io/VO2Cue/) or [download VO2Cue on the App Store](https://apps.apple.com/us/app/vo2cue/id6804899072).

## Open Source & Contributor Rewards

VO2Cue is released under the [MIT License](LICENSE). You are free to use, modify, and redistribute the code under its terms.

Help make VO2Cue better. Bug fixes, features, accessibility improvements, documentation, and tests are all welcome. You can also help by reporting bugs or suggesting ideas in [GitHub Issues](https://github.com/GreggRoll/VO2Cue/issues).

**Get a free lifetime subscription to VO2Cue when your pull request is accepted and merged.** A successful merge request (MR)—called a pull request (PR) on GitHub—is one reviewed, accepted, and merged by the maintainer. After your PR is merged, ask in the PR thread to arrange your reward; do not post private account or payment details publicly.

Start with the [contribution guide](CONTRIBUTING.md) for the workflow and reward details. For a larger change, open an issue first to discuss the idea.

## Product Positioning

VO2Cue helps athletes complete Norwegian-style 4x4 sessions without staring at a clock. The app is designed around Apple Watch haptics first, with optional tones and voice cues for people who train in the pool, on a treadmill, on a bike, or anywhere a visual timer gets in the way.

The launch version is designed as a complete paid iOS app with an independent Apple Watch companion.

## V1 Features

- Run a default 4x4 VO2 session: warmup, four hard intervals, active recovery periods, and optional cooldown.
- Let users customize work duration, rest duration, loop count, countdown length, cue labels, warmup, and cooldown.
- Provide eyes-free guidance with Watch haptics, tones, and optional spoken cues.
- Support swimming as a primary use case while keeping the app useful for running, cycling, rowing, and gym cardio.
- Save completed workouts to Apple Health when the user grants permission.
- Show simple local history such as completed sessions, total minutes, and recent workouts.
- Keep the app private: no account, no ads, and no third-party tracking. Only user-submitted feedback leaves the device through the feedback delivery service.

## Default Workout

The default workout follows a classic 4x4 structure:

- Warmup: 10 minutes
- Hard interval: 4 minutes
- Active recovery: 3 minutes
- Repeats: 4
- Cooldown: optional

Users can customize the default session or create their own profiles.

## Cue System

VO2Cue is designed for workouts where looking at the screen is inconvenient or impossible.

- Haptics are the primary cue on Apple Watch.
- Tones distinguish countdown, start, sprint, recovery, halfway, and finish states.
- Voice cues can announce phrases such as "3, 2, 1", "Sprint", "Recover", and "Workout complete".
- Cue labels are customizable so users can choose words like Start, Sprint, Hard, Rest, Recover, Easy, or Jog.
- Cue settings can be customized per workout profile.

## Accessibility

The core accessibility promise is eyes-free completion: a user should be able to start a workout and finish it without reading the screen.

V1 accessibility support includes:

- VoiceOver-friendly controls and labels.
- Voice Control-friendly buttons and navigation.
- Large text and Dynamic Type support.
- High contrast layouts.
- Reduced motion support.
- Phase states that are not communicated by color alone.
- Clear haptic, audio, and visual alternatives for key workout events.

## Apple Watch And Health

The independent Apple Watch app can serve as the main workout runtime.

- Start, pause, resume, skip, and end workouts from the watch.
- Use Watch haptics for interval transitions and countdowns.
- Sync custom workout profiles with activation-safe delivery, automatic retries, and visible sync status on iPhone.
- Request HealthKit permissions only when needed.
- Show progress and a clear result when requesting Health access, including a route to Settings after denial.
- Save completed workouts to Apple Health.
- Handle permission denial gracefully.

## Pricing

VO2Cue is planned as a $1.99 paid app on the iOS App Store.

The paid launch version should feel complete without requiring additional purchases. Optional future monetization may include voice packs, tone packs, and advanced workout templates, but the base timer, Apple Watch support, accessibility features, and HealthKit integration should remain part of the core product.

Contributors whose pull requests are accepted and merged receive a **free lifetime subscription to VO2Cue**. See the [contributor reward details](CONTRIBUTING.md#free-lifetime-subscription).

## Next release: consistency and progress

The next release adds a private, on-device training habit loop:

- An editable weekly active-minute goal, initially 60 minutes as a personal target.
- A workout library with Norwegian 4×4 (35 minutes), Short Intervals (22 minutes), and Easy 20 (20 minutes), each previewable and editable after adding.
- Actual training-time tracking that excludes pauses and skipped intervals, with phase breakdowns and skipped-phase counts on iPhone and Apple Watch.
- A Progress tab with eight weeks of active-minute totals, workout details, and optional effort ratings and notes.
- Optional weekday reminders at a chosen local time. Reminders default off and open Workouts without starting a session.

Sessions ended early contribute their actual minutes. Existing history stays readable and labels legacy durations as recorded time; those entries are excluded from goals and charts because skipped time cannot be reconstructed. Sessions count toward the week they started, using the user's calendar and local timezone. Deleting local history removes its notes and recalculates progress, without deleting Apple Health workouts.

Goals, notes, and reminder settings stay on the iPhone. Watch records continue to transfer directly through WatchConnectivity. There is no new account, backend, analytics, Health permission, or purchase tier. No follow-up feature roadmap is planned in this change.

See [next-release validation](docs/next-release-validation.md) for automated coverage and the physical-device checks required before release.

## Privacy

VO2Cue is private by default. The complete [Privacy Policy](https://greggroll.github.io/VO2Cue/privacy) explains the app's data handling and HealthKit use.

- No account required.
- No ads.
- No third-party analytics.
- Core workouts work without a backend. Optional feedback uses FormSubmit to deliver the subject and message to the developer.
- Workout profiles, history, goals, effort ratings, notes, and reminder settings stay in the app's local storage.
- Health data is accessed only with permission and stays on the user's devices and in Apple Health.
- iPhone and Apple Watch exchange profiles and completed workout records directly through Apple's WatchConnectivity framework.
- Users can revoke Health access in Apple settings and delete local history from the app.

## Development Status

V1 is implemented as a native SwiftUI project for iOS 17+ and watchOS 10+. Version 1.0, build 2 was uploaded to TestFlight and reached Apple's `VALID` processing state on August 28, 2026.

The current build includes:

- The classic 35-minute Norwegian 4x4 profile, plus create, edit, duplicate, and delete support for custom profiles.
- Custom warmup, work, recovery, repeat count, optional cooldown, countdown length, activity type, cue labels, haptics, tones, voice, and halfway cues.
- A wall-clock-based workout engine with start, pause, resume, skip, early end, phase transitions, countdowns, and completion handling.
- An independent Apple Watch app with haptic-first cues, live controls, HealthKit workout sessions, and live heart rate when permission is available.
- Activation-safe WatchConnectivity profile sync from iPhone, immediate acknowledged delivery when reachable, durable queued delivery when disconnected, automatic retries, and completed-session transfer back to iPhone.
- Optional HealthKit workout saving with accurate authorization state, visible request progress and results, Settings recovery after denial, and graceful failure handling.
- Private on-device JSON persistence for profiles and workout history.
- Accessible SwiftUI controls, Dynamic Type, VoiceOver descriptions, high-contrast phase labels and icons, reduced-motion behavior, and non-color phase communication.
- No tracking, account, analytics SDK, or ads. Optional feedback is declared as customer support data.
- Deterministic unit and UI tests covering timing, cues, Watch payloads, purchases, onboarding, profiles, progress, workout notes, and reminders.

## Project Structure

- `VO2Cue/Shared`: workout profiles, phase timeline, runtime, cues, and persistence shared by iOS and watchOS.
- `VO2Cue/VO2CueApp`: iPhone setup, profile editor, live runtime, history, settings, HealthKit, and WatchConnectivity.
- `VO2Cue/VO2CueWatch`: independent Watch UI, live HealthKit workout session, heart rate, haptics, and sync.
- `VO2Cue/VO2CueTests`: deterministic unit tests for the workout engine.
- `VO2Cue/VO2CueUITests`: end-to-end iPhone UI tests.

## Build And Test

Requirements:

- Xcode 26 or newer.
- iOS 17+ and watchOS 10+ deployment targets.
- A development team with HealthKit capability enabled for signed device builds.

Open `VO2Cue.xcodeproj` and run the shared `VO2Cue` scheme. The iPhone app embeds the independent `VO2CueWatch` app.

Command-line checks:

```sh
xcodebuild \
  -project VO2Cue.xcodeproj \
  -scheme VO2Cue \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-

xcodebuild \
  -project VO2Cue.xcodeproj \
  -scheme VO2Cue \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

HealthKit cannot be fully exercised without granting permission on a simulator or signed Apple device. Denial is intentionally non-blocking: VO2Cue continues to time workouts and store local history.

Purchase integration tests use a hosted app and local StoreKit configuration. Use the **VO2Cue Purchases** scheme for local checkout testing; see the [release setup and simulator notes](docs/monetization-release.md).

## Feedback and rating requests

Settings ends with an in-app feedback form (required subject, optional message). Delivery uses FormSubmit’s invisible-email identifier in `FeedbackService.formIdentifier`; never substitute the recipient email. Activate the form using the inbox verification email before setting this identifier and testing a submission. An empty identifier fails safely without claiming delivery.

Four introduction pages explain the fitness benefits, eyes-free cues, Norwegian 4×4, custom workouts, Watch support, history, and optional Apple Health saving. New free downloads then reach a hard paywall with monthly membership or one-time lifetime access; existing paid-app buyers retain lifetime access. See the [monetization release setup](docs/monetization-release.md) before changing the download price to Free. Settings includes purchase restoration and a way to replay the introduction.

StoreKit rating requests are attempted with a 25% chance after completed phone workouts, at most once every 120 days and three times in a rolling year. Apple decides whether to show the dialog and does not report review completion. Settings includes a direct App Store review link and an “already reviewed” toggle that disables future requests. Native prompts do not appear in TestFlight.


## Lock-screen workouts

Phone workouts with tones or voice enabled play a scheduled audio program in the background, including the timed gaps between cues. Audio mixes with other apps' music. Pause stops playback; resume and skip rebuild the remaining program using active workout time. A call, disconnected audio route, or audio-engine interruption pauses the workout for an explicit resume.

A Live Activity displays the workout name, phase, round, next phase, and system-rendered countdown on the Lock Screen and Dynamic Island. It starts with a phone workout, freezes while paused, and ends with the workout. Live Activities must be allowed in iOS Settings. With both tones and voice disabled, iOS may suspend phase updates in the background; a stale activity asks the user to reopen VO2Cue.

Add the **Weekly goal** widget from the Home Screen widget gallery in small or medium size. Both sizes show active minutes, goal completion, and a progress ring. Tap the progress area to open Progress. The medium widget also shows the most recently started phone workout (or the first saved workout before one has been started); **Start workout** opens VO2Cue and starts that profile after onboarding and purchase access are verified. It keeps an existing workout running. Goal edits, saved phone/Watch sessions, history deletion, and profile changes refresh the widget, and the week resets using the local calendar.

The iPhone app and widget extension share `group.com.gregadams.vo2cue.shared`. Enable this App Group for both bundle IDs in the Apple Developer account and include it in their provisioning profiles before a device or TestFlight build. The existing manual widget distribution profile must be regenerated with this entitlement.

Before release, test on a physical iPhone without a debugger: lock during a long warmup, listen through halfway/countdown/phase changes and completion, repeat with voice only and tones only, and check pause/resume/skip, music mixing, headphones disconnecting, and a phone call. Simulator checks cannot establish real-device locked-screen audio reliability.
