# Research: extended_image overview

- **Query**: Evaluate `extended_image` for replacing custom InteractiveViewer + PageView + ScrollPhysics in export-screen fullscreen preview.
- **Scope**: external (pub.dev + GitHub `fluttercandies/extended_image`)
- **Date**: 2026-05-22
- **Sources**: `pub.dev/api/packages/extended_image`, `pub.dev/api/packages/extended_image/score`, `api.github.com/repos/fluttercandies/extended_image`, repo CHANGELOG / README / LICENSE, GitHub issue search.

## 1. Latest version & SDK constraints

- **Latest stable**: **`10.0.1`**, published **2025-04-21**.
- **Pubspec constraints** (from `latest.pubspec.environment`):
  - Dart SDK: `>=3.7.0 <4.0.0`
  - Flutter SDK: `>=3.29.0`
- **Compatibility with this project**: project pubspec pins `sdk: ^3.10.8` (Dart), so the Dart range is satisfied. Flutter must be `>=3.29.0` — any Flutter that ships Dart 3.10.x is well above 3.29, so OK.
- Pub.dev tags include `is:dart3-compatible` and `is:wasm-ready`.
- Score: granted 150 / 160 points; 2,016 likes; 235,778 downloads in last 30 days.

## 2. Transitive dependencies & conflict check

`extended_image 10.0.1` declares only:

| Direct dep | Constraint |
|---|---|
| `extended_image_library` | `^5.0.0` |
| `meta` | `^1.7.0` |
| `vector_math` | `^2.1.4` |
| `flutter` (SDK) | — |

`extended_image_library 5.0.1` (latest, published 2025-05-30) pulls:

| Transitive dep | Constraint |
|---|---|
| `crypto` | `^3.0.0` |
| `http_client_helper` | `^3.0.0` |
| `js` | `>=0.6.0 <0.8.0` |
| `path` | `^1.9.0` |
| `path_provider` | `^2.1.0` |
| `web` | `>=0.3.0 <10.0.0` |

Cross-check against this project's `pubspec.yaml`:

| Project dep | Project constraint | Verdict |
|---|---|---|
| `flutter_riverpod ^2.6.1` | independent | no overlap |
| `image ^4.3.0` | independent (extended_image does NOT depend on `package:image`) | no overlap |
| `super_drag_and_drop ^0.9.0` | independent | no overlap |
| `super_clipboard ^0.9.0` | independent | no overlap |
| `archive ^4.0.0` | independent | no overlap |
| `gal ^2.3.0` | independent | no overlap |
| `share_plus ^10.1.2` | independent | no overlap |
| `google_fonts ^8.1.0` | independent | no overlap |
| `web ^1.1.0` | shared transitive | **compatible** (extended_image_library accepts `>=0.3.0 <10.0.0`, so 1.1.x satisfies) |
| `path ^1.9.0` | shared transitive | identical constraint — compatible |
| `path_provider ^2.1.5` | shared transitive | compatible (extended_image_library wants `^2.1.0`) |

Old historical worry — `http_client_helper` — exists, but it is now at `^3.0.0` and only used internally by `extended_image_library`; no other project dep declares it.

**No version-solver conflicts expected.** Confirm by running `flutter pub upgrade --dry-run` before adding it.

Caveat: `js` is a soft red flag. The `js >=0.6.0 <0.8.0` constraint is the legacy `package:js`, but the package has already migrated to `package:web` + `dart:js_interop` (commit `xkeyC 2025-02-28: feat: Migrate to package:web and dart:js_interop (#733)`), so `js` is likely only used as a stub on non-web or for older paths. Should not block the build.

## 3. Platform support matrix

pub.dev platform tags for `10.0.1`:

- `platform:android` — yes
- `platform:ios` — yes
- `platform:macos` — yes
- `platform:linux` — yes
- `platform:windows` — yes
- `platform:web` — yes (also `is:wasm-ready`)

Gesture / gallery features (`ExtendedImage` zoom/pan, `ExtendedImageGesturePageView`) are part of the core Dart-only widget tree, so they run on all six platforms. The web demo is live at `https://fluttercandies.github.io/extended_image/`.

Known web-specific behavior:

- `10.0.0` added `WebHtmlElementStrategy for ExtendedNetworkImageProvider on Web` — separate strategy for HTML `<img>` element vs canvas; matters for **network** images. For our case (local in-memory bytes from the editor pipeline), default canvas drawing applies.
- 19 open issues mention "web", mostly about network-image CORS, large-image loading on iOS Safari, and crop-on-web sizing (older, pre-10.0). Nothing fundamental about gesture/pan being broken on web.
- Linux: issue **#760** reports Live Photos not supported on Linux (Apple-specific media format; unrelated to PNG/JPEG export).

## 4. Maintenance signals

- **Stars**: 2,052; **forks**: 520.
- **Issues**: 52 open / 573 closed → ~8.3% open ratio (healthy).
- **Last commit to repo**: `2025-04-21` (≈13 months before today, 2026-05-22).
- **Last release**: `10.0.1` on 2025-04-21.
- **Maintainer (`zmtzawqlp`) recent public activity**: actively pushing to `HarmonyCandies/.github` as of `2026-05-22`. Maintainer is active on GitHub but has shifted focus to other org (HarmonyCandies) work.
- **Recent bug report engagement**: issue **#761** (open, 2026-02-22, ExtendedImageGesturePageView on iOS, 10.0.1) has **0 comments** after 3 months — slow triage on newest issues.
- **Companion package** `extended_image_library 5.0.1` published `2025-05-30`, so the sister library is one month newer than the main package — sub-package still receives drops.

**Verdict for long-term dependency**: package is widely used (235k monthly downloads), MIT-licensed, healthy issue ratio, but maintainer cadence has slowed in 2026. Acceptable to depend on; budget for the possibility of needing a fork or manual patch if a regression appears on a future Flutter SDK bump.

## 5. License

- **MIT** (`fluttercandies/extended_image/LICENSE`, copyright 2019 zmtzawqlp).
- Pub.dev confirms: `license:mit`, `license:osi-approved`, `license:fsf-libre`.
- No commercial-use restrictions.

## 6. Notable bugs / gotchas for gesture mode and `ExtendedImageGesturePageView`

Pulled from open-issue searches against `gesture` and `ExtendedImageGesturePageView`:

- **#761** (open, 2026-02-22, 10.0.1, iOS) — Bug report for `ExtendedImageGesturePageView.builder` with `ExtendedImage.file` and `BoxFit.con…`. No maintainer comment yet. Worth watching since version matches what we'd adopt.
- **#752** (open, 2025-10-01) — Feature request: expose `allowImplicitScrolling` so the page view can pre-build adjacent pages. Currently unavailable; reporter cites split-second blank/loading state when swiping horizontally even with `precacheImage`. If our preview needs prefetched neighbours, this is a real limitation.
- **#736** (open, 2025-04-14, 16 comments, Android, 9.1.0) — Single-finger vertical swipe on `ExtendedImageGesturePageView` is often rejected by the gesture arena, `ExtendedVerticalDragGestureRecognizer` loses, swipe gets cancelled. Active community discussion, no fix landed.
- **#648** (open, 2024-01-15) — Fast horizontal swipe between pages is not smooth.
- **#677** (open, 2024-05-15) — Mixed long-image + normal-image gallery has issues.
- **#686** (open, 2024-07-03) — When zoomed to minimum scale, after pan + release the image "sticks" and doesn't bounce back to original size.
- **#673** (open, 2024-04-20) — Mouse-wheel zoom-out does not honor configured speed.
- **#442** (open, 2022-01-04) — Image cropper zoom-out gesture not working (cropper-specific, not preview).
- **#762** (open, 2026-05-02) — Feature request: support gesture zoom/pan for arbitrary widget content (not blocking, but indicates `ExtendedImageGesture` is currently locked to `ExtendedImage`).

### Practical gotchas to validate during integration

1. `ExtendedImageGesturePageView` does **not** expose `allowImplicitScrolling` (#752). If our use case relies on adjacent-page pre-build, this is a missing knob.
2. Vertical-drag gesture arena conflicts (#736) — if the preview also needs to coexist with a vertical swipe-to-dismiss / slide-out-page, expect tuning.
3. Bounce-back to min-scale is not automatic when over-panned at min zoom (#686). The library has `inPageView` and `GestureConfig.inertialSpeed`, but the bug is open.
4. Network-image-on-web has a separate strategy added in 10.0.0 (`WebHtmlElementStrategy`); for **memory image** sources (typical export preview), the default canvas path is used — no extra configuration.
5. The `js` legacy dep in `extended_image_library` (`>=0.6.0 <0.8.0`) is a soft signal — should not break, but watch when Flutter eventually drops `package:js` entirely.

## Caveats / Not found

- No bug list explicitly tied to `image ^4.3.0` interop — `extended_image` does not consume `package:image`, so no functional overlap was identified.
- Did not verify Flutter ^3.29 vs the exact Flutter version bundled with Dart 3.10.8 — assumed compatible.
- Did not fetch a full transitive lockfile; the conflict analysis above is based on declared constraints only. Final confirmation should be `flutter pub upgrade --dry-run` after adding the dep.
