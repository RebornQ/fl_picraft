# Manual Test Plan — Polish & Multi-Platform

This checklist covers the parts of `polish-platform-test` that **cannot**
be verified by headless tests:

1. Cold-start latency on real mobile devices (PRD §7: < 2 s)
2. Peak memory while processing 20 large images (PRD §7: < 500 MB)
3. End-to-end smoke test on each of the 6 supported platforms

The headless `flutter test --tags benchmark` harness records the
**stitch + grid render baselines** (see `audit-report.md` Round 3) and
should be re-run before every release. This document covers what the
benchmark cannot.

> Convention: each section ends with a checklist the test runner ticks
> off and pastes the result into the PR description.

---

## A. Cold-start latency

PRD §7 budget: **app cold start to interactive < 2 s** on a mid-tier
mobile device.

### How to measure

#### Android (preferred — repeatable via adb)

```bash
# 1. Build release APK on the host
flutter build apk --release

# 2. Install on the device
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 3. Force-stop so the next launch is a true cold start
adb shell am force-stop com.fl_picraft

# 4. Measure with `am start -W` (waits for the activity to draw)
adb shell am start -W -n com.fl_picraft/.MainActivity

# Output looks like:
#   Status: ok
#   LaunchState: COLD
#   Activity: com.fl_picraft/.MainActivity
#   TotalTime: 1234   <-- this is the cold-start budget metric
#   WaitTime: 1290
```

**Pass criterion**: `TotalTime` < 2000 ms on three consecutive cold
starts (force-stop between each). Average and worst-case both must
clear the bar.

> Note: `TotalTime` is "until the first frame is drawn", which matches
> the PRD's "to interactive" phrasing — the home-screen feature cards
> render in the first frame so they are tappable immediately.

#### iOS (requires Xcode Instruments)

```bash
# 1. Build & install via flutter run --release on a tethered device
flutter run --release -d <ios-device-id>

# 2. In Xcode → Product → Profile → "App Launch" template
# 3. Force-quit the app from the multitask switcher
# 4. Click Record, tap the app icon on the home screen
# 5. Stop after the home screen renders
# 6. Read the "Time to First Frame" metric in the Launch Phases view
```

**Pass criterion**: same as Android — < 2 s total to first frame on
three consecutive cold starts.

### Mid-tier device list (calibration baseline)

| Platform | Device | Year | Tier rationale |
|----------|--------|------|----------------|
| iOS | iPhone SE 2nd gen / iPhone 11 | 2020 / 2019 | Cheapest currently-supported iOS hardware |
| Android | Pixel 5 / Galaxy A53 | 2020 / 2022 | Mid-tier 2020-era SoC, common test target |

If launching on flagship-class hardware (iPhone 15, Pixel 9), expect
launch times well under the budget — the budget is set against the
mid-tier hardware above.

### Cold-start checklist

- [ ] iOS device cold start measured (3 runs, all < 2000 ms)
- [ ] Android device cold start measured (3 runs, all < 2000 ms)
- [ ] Failure case logged if any run > 2000 ms (link DevTools snapshot)

---

## B. Peak memory during 20-image processing

PRD §7 budget: **peak memory < 500 MB** while processing large images.

### How to measure

#### Flutter DevTools — Memory profiler

```bash
# 1. Launch in profile mode (release perf, debug-attachable)
flutter run --profile -d <device-id>

# 2. Open DevTools at the URL printed by `flutter run`
# 3. Click the Memory tab
# 4. Click "Pause" then "Clear" to start with a clean baseline
```

Reproduction steps inside the running app:

1. Tap "Long Stitch" feature card from the home screen
2. Tap "Add images" → select 20 large photos (≥ 5 MP each, JPEG)
3. Wait for the strip to populate (all 20 thumbnails visible)
4. Take memory snapshot — note the value (this is "loaded" baseline)
5. Tap export → "Save to Gallery" (PNG, max quality)
6. Watch the memory graph during the render phase
7. Take memory snapshot at the peak — note the value
8. After save completes, take a third snapshot (steady state)

### Pass criterion

- **Peak** < 500 MB on the device during step 6
- **Steady state** (post-export) returns to within 50 MB of the loaded
  baseline (i.e. no leaked image bytes)

### Test-asset prep

Drop 20 photos into `~/Pictures/test-assets/large/` matching:

| Image | Resolution | Size | Notes |
|-------|------------|------|-------|
| 1–10 | 4032×3024 (iPhone) | ~3 MB JPEG | Real camera output |
| 11–15 | 6000×4000 (DSLR) | ~5 MB JPEG | Higher resolution stress |
| 16–20 | 1920×1080 (screenshot) | ~500 KB PNG | PNG decode path |

Mixing JPEG and PNG ensures both decode paths (libjpeg vs libpng) get
exercised in the same session.

### Memory checklist

- [ ] iOS profile-mode DevTools session captured (all 3 snapshots)
- [ ] Android profile-mode DevTools session captured (all 3 snapshots)
- [ ] Peak memory recorded for each platform
- [ ] Steady state confirmed (no leak)
- [ ] Failure case logged if any peak > 500 MB

---

## C. Six-platform compatibility matrix

PRD §7: every supported platform must complete the four core flows
without crashing. PRD platform table:

| Platform | Min version |
|----------|-------------|
| iOS | 12+ |
| Android | 6+ (API 23) |
| macOS | 11+ |
| Windows | 10+ |
| Linux | Ubuntu 20.04+ |
| Web | Chrome / Edge / Safari latest |

### Must-pass flows per platform

For each platform, run these 4 flows end-to-end and tick the boxes:

#### Flow 1 — Long stitch (vertical, 5 images, PNG export)

1. Launch app, tap "Long Stitch" card
2. Import 5 images via the platform's primary picker:
   - iOS / Android: gallery (`image_picker`)
   - macOS / Win / Linux: file dialog (`file_picker`) **or** drag-drop
   - Web: file input
3. Verify thumbnails appear in the strip in the order you picked
4. Verify the preview canvas shows them stitched vertically
5. Tap "Export" → set format = PNG, max quality
6. Tap "Save to gallery" / "Download"
7. Verify success snackbar (mentions location on desktop)
8. Open the saved file and verify it matches the preview

#### Flow 2 — Long stitch (horizontal, movie-subtitle mode, JPEG export)

1. Add 4 images
2. Switch mode to "Vertical" (if not already)
3. Toggle "subtitle-only mode" on
4. Drag the subtitle band slider to ~150 px
5. Verify only the bottom band of images 2–4 is visible in preview
6. Export as JPEG quality 85
7. Verify the saved file matches the preview

#### Flow 3 — Grid split (regular 3×3, PNG export)

1. Tap "Grid Split" card
2. Pick a single source image
3. Select grid type = 3×3 (default)
4. Verify the canvas shows a 3×3 grid overlay
5. Tap export → PNG → save
6. Verify 9 separate files (or 9 success notifications) saved

#### Flow 4 — Grid split (nine-grid social, custom center)

1. With a 3×3 grid loaded, toggle "Nine-grid social mode" on
2. Verify the canvas auto-crops to square
3. Tap "Replace center image", pick a different photo
4. Pinch / drag the center cell to adjust scale & position
5. Export → save → verify 9 cells, with cell 5 showing the
   replacement image at the chosen scale/position

### Per-platform extras

Platform-specific edge cases to verify on top of the 4 flows above:

#### iOS

- [ ] Photos add-only permission prompt fires once on first save
- [ ] Camera capture flow works (test on iPhone, not simulator —
      simulator camera is mocked)
- [ ] Universal clipboard image paste (copy from Photos → paste in
      app)

#### Android

- [ ] Storage permission flow on API 23 (Marshmallow) — old runtime
      perms model
- [ ] API 30+ scoped storage works (`gal` should handle this)
- [ ] System share-target intent (long-press image elsewhere → share to
      Fl PiCraft) — currently expected to be unsupported, verify graceful
      no-op or absence from share menu
- [ ] Drag-drop disabled gracefully (Android tablet with mouse) — no
      crash, no broken UI

#### macOS

- [ ] Drag-drop from Finder works (multi-select)
- [ ] File dialog save with custom filename works
- [ ] Light → dark mode toggle while app open re-renders correctly

#### Windows

- [ ] Drag-drop from File Explorer works (multi-select)
- [ ] File dialog save respects file extension filter
- [ ] HiDPI scaling (125% / 150% / 200%) — UI doesn't clip

#### Linux (Ubuntu 20.04 GNOME)

- [ ] Drag-drop from Files app works
- [ ] File dialog save works (Zenity / native)
- [ ] Wayland session works in addition to X11

#### Web

- [ ] Chrome blob download (file ends up in browser's download dir)
- [ ] Edge blob download
- [ ] Safari blob download (Safari is most fragile re: download API)
- [ ] Image clipboard paste — note: Safari requires a user gesture
      and may show a permission prompt
- [ ] No drag-drop on web (currently disabled by `kIsWeb` guard) —
      verify the entry point is hidden / disabled cleanly

### Per-platform compatibility checklist

For each row, tick all 4 flows + platform extras:

#### iOS (12+)

- [ ] Flow 1 — vertical PNG
- [ ] Flow 2 — movie-subtitle JPEG
- [ ] Flow 3 — regular 3×3
- [ ] Flow 4 — nine-grid social
- [ ] iOS extras

#### Android (6+ / API 23)

- [ ] Flow 1
- [ ] Flow 2
- [ ] Flow 3
- [ ] Flow 4
- [ ] Android extras

#### macOS (11+)

- [ ] Flow 1
- [ ] Flow 2
- [ ] Flow 3
- [ ] Flow 4
- [ ] macOS extras

#### Windows (10+)

- [ ] Flow 1
- [ ] Flow 2
- [ ] Flow 3
- [ ] Flow 4
- [ ] Windows extras

#### Linux (Ubuntu 20.04+)

- [ ] Flow 1
- [ ] Flow 2
- [ ] Flow 3
- [ ] Flow 4
- [ ] Linux extras

#### Web (Chrome / Edge / Safari latest)

- [ ] Flow 1 — Chrome
- [ ] Flow 1 — Edge
- [ ] Flow 1 — Safari
- [ ] Flow 2 — Chrome
- [ ] Flow 3 — Chrome
- [ ] Flow 4 — Chrome
- [ ] Web extras

---

## D. Reporting

For each section that fails, capture and attach:

1. Platform + version (e.g. "iOS 17.4 on iPhone SE 2nd gen")
2. Reproduction steps that diverge from the checklist
3. Screen recording or DevTools snapshot
4. Current PR / commit SHA

File the failure as a separate task entry under
`.trellis/tasks/<next-id>-<short-name>/` so the polish task can ship
without blocking on regressions found here.
