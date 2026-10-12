# VO2Cue App Store screenshots

Final deliverables:

- `final/iphone-1242x2688/` — six benefit-led iPhone marketing screenshots
- `final/watch-422x514/` — three native Apple Watch Ultra 3 screenshots
- `final/ipad-2064x2752/` — three benefit-led 13-inch iPad screenshots

## Recommended App Store order

### iPhone

1. Train hard. Not the clock.
2. Your workout. Your way.
3. One coach for every cardio day.
4. The same workout. Right on your wrist.
5. Progress that stays yours.
6. Your goal. One tap closer.

### Apple Watch Ultra 3

1. Workout library
2. Live interval
3. Workout controls

### iPad

1. Your interval command center.
2. Big, clear, ready for hard efforts.
3. Momentum you can measure.

## Production notes

- App UI was captured from the real `VO2Cue` and `VO2CueWatch` simulator builds.
- Apple Watch images were captured natively from the Apple Watch Ultra 3 (49mm) simulator at 422 × 514 px.
- iPad images were captured natively from the iPad Pro 13-inch simulator at 2064 × 2752 px.
- iPhone simulator captures were placed into exact 1242 × 2688 px App Store canvases.
- Representative demo profiles and workout history were used to show the app in a populated state.
- Slides 3 and 5 use current Workouts and Progress captures. Slide 6 features real small and medium widget captures with 42 of 60 minutes (70%), plus a completed goal example at 42 of 40 minutes. Widget crops retain the actual UI; only their placement and rounded outer masks are composited.
- The widget and current app captures also generate the demo page assets in `docs/demo/assets/` through `export_web_assets()`.
- The visual background was generated with the built-in image-generation tool. Screens originate from simulator captures; iPhone slides 1 and 4 use a color-corrected derivative of the timer capture (see below).

## Timer color correction

`sources/iphone/runtime-sprint-neutral.png` is the built-in imagegen derivative used by iPhone slides 1 and 4. The original `runtime-sprint.png` is retained. The edit prompt requested a neutral white main background and light gray Next/Recover card while preserving the existing text, icons, layout, and orange/red button accents. Final exports remain 1242 × 2688 pixels. This changes the marketing assets, not the app's runtime appearance.

## Background-generation prompt

> Create a sophisticated abstract portrait background that conveys VO2 intensity, breath, momentum, and calm control; sweeping translucent energy ribbons and a subtle pulse-wave rhythm, suitable behind real iPhone and iPad UI screenshots. Deep near-black navy fading into warm sunrise orange and controlled electric red, with a small cool-blue recovery accent. Polished editorial 3D light-and-atmosphere artwork, premium and restrained. Darkest and simplest in the upper quarter for white headline copy, richer flowing energy through the middle and lower third. No people, products, devices, UI, logos, text, numbers, or watermark.

The reproducible compositing script is `compose_screenshots.py`.
