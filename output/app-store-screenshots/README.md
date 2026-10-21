# VO2Cue App Store screenshots

Final deliverables:

- `final/iphone-1206x2622/` — six upload-ready screenshots at **1206 × 2622 px**
- `vo2cue-iphone-widgets.zip` — the same six upload images packaged for delivery
- `final/iphone-1242x2688/` — six benefit-led iPhone marketing screenshots
- `final/watch-422x514/` — three native Apple Watch Ultra 3 screenshots
- `final/ipad-2064x2752/` — three benefit-led 13-inch iPad screenshots

## Recommended App Store order

### iPhone

1. Find your range. Own your effort. — Watch heart rate and range slider
2. Your workout. Your way.
3. One coach for every cardio day.
4. Every interval. Every heartbeat. — interval graph and heart-rate targets on both screens
5. Progress that stays yours.
6. Your goal. One tap closer.

### Apple Watch Ultra 3

1. Hard interval — live BPM, in-range marker, and hard target
2. Recovery interval — live BPM and the lower recovery target
3. Workout timeline — measured BPM line and target guidance across cycles

### iPad

1. Your interval command center.
2. Big, clear, ready for hard efforts.
3. Momentum you can measure.

## Production notes

- App UI was captured from the real `VO2Cue` and `VO2CueWatch` simulator builds.
- Apple Watch images were captured natively from the Apple Watch Ultra 3 (49mm) simulator at 422 × 514 px.
- iPad images were captured natively from the iPad Pro 13-inch simulator at 2064 × 2752 px.
- iPhone simulator captures were placed into exact 1242 × 2688 px App Store canvases.
- The upload exports are 1206 × 2622 px RGB PNGs. The original composition is scaled proportionally with a small background extension to preserve all content. The 1242 × 2688 originals do not match the 6.1-inch / 6.3-inch slot.
- Representative demo profiles and workout history were used to show the app in a populated state. The heart-rate captures use a maximum of 180 BPM, hard targets of 153–171 BPM, recovery targets of 108–126 BPM, and simulated sensor readings. They demonstrate the product UI rather than a recorded person's workout.
- Slides 3 and 5 use current Workouts and Progress captures. Slide 6 features real small and medium widget captures with 42 of 60 minutes (70%), plus a completed goal example at 42 of 40 minutes. Widget crops retain the actual UI; only their placement and rounded outer masks are composited.
- The widget and current app captures also generate the demo page assets in `docs/demo/assets/` through `export_web_assets()`.
- The visual background was generated with the built-in image-generation tool. The new heart-rate screens are unretouched simulator UI; only cropping, placement, scaling, rounded masks, and surrounding marketing artwork are composited. Slide 4 enlarges the complete native iPhone graph card alongside the Watch range view.

## Capturing heart-rate screens

- Build the Debug iPhone and Watch apps. Use a 1206 × 2622 iPhone simulator and the Apple Watch Ultra 3 (49mm) simulator. Override the iPhone status bar to 9:41 before capture; watchOS does not support simulator status-bar overrides.
- Launch with `-heartSyncFixture work -appStoreScreenshots` for the hard interval, or `-heartSyncFixture recovery -appStoreScreenshots` for recovery. On iPhone also pass `-hasCompletedOnboarding YES -hasAlreadyReviewed YES -purchaseFixture paid -healthSavingEnabled NO`.
- These flags seed representative data only in Debug builds. The normal debugging fixture retains its visible debug label unless `-appStoreScreenshots` is explicitly present. Neither launch path is included in distribution builds.
- iPhone: run `VO2CueUITests/testAppStoreHeartRateScreenshots` and export its screenshot attachments with `xcrun xcresulttool export attachments`. Save the work, recovery, and timeline captures as `sources/iphone/heart-rate-{work,recovery,timeline}.png`.
- Watch: capture the hard and recovery timer pages, then tap the heart-rate readout to open the timeline. Use `xcrun simctl io <watch-simulator-id> screenshot <path>.png` for native PNG captures, and save them as `sources/watch/heart-rate-{work,recovery,timeline}.png`. The compositor rejects non-native Watch dimensions.
- Keep temporary build data, test results, and review images outside the repository. The earlier `runtime-sprint-neutral.png` derivative is retained as an older source; it is no longer used by the iPhone exports.

## Background-generation prompt

> Create a sophisticated abstract portrait background that conveys VO2 intensity, breath, momentum, and calm control; sweeping translucent energy ribbons and a subtle pulse-wave rhythm, suitable behind real iPhone and iPad UI screenshots. Deep near-black navy fading into warm sunrise orange and controlled electric red, with a small cool-blue recovery accent. Polished editorial 3D light-and-atmosphere artwork, premium and restrained. Darkest and simplest in the upper quarter for white headline copy, richer flowing energy through the middle and lower third. No people, products, devices, UI, logos, text, numbers, or watermark.

The reproducible compositing script is `compose_screenshots.py`; it refreshes the canonical 1206 × 2622 export folder and the widget ZIP. Duplicate `final 2`, `final 3`, and unpacked widget export folders have been retired.

Run on macOS with Pillow installed:

```sh
python3 output/app-store-screenshots/compose_screenshots.py
```

To update only the iPhone and Watch deliverables, preserving iPad and website assets:

```sh
python3 output/app-store-screenshots/compose_screenshots.py --platforms iphone watch
```
