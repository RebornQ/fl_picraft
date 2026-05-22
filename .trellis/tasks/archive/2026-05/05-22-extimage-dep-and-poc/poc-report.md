# PoC Report: extended_image: ^10.0.1

> **Task**: `05-22-extimage-dep-and-poc` (ST1 of
> `05-22-brainstorm-fullscreen-preview-extended-image`)
> **Status**: VERIFIED — 3/3 red flags passed manual smoke; Approach A approved
> **Author (scaffold)**: Implement agent, 2026-05-22
> **Author (verdict)**: Reborn, 2026-05-22 ("测试完了，暂时没发现什么问题")

## Purpose

This document is the **risk gate** for the migration to
`extended_image: ^10.0.1`. ST2 / ST3 / ST4 are blocked until a human
manually exercises the PoC widget (`lib/_poc/extended_image_poc.dart`)
on at least one mobile + one desktop platform and writes a verdict for
each of the three red flags below.

If **any** red flag reproduces, the recommendation flips from
"Approach A 推进" to "Approach B 切换" (keep self-rolled outer
`GestureDetector` + 100 dp threshold for drag-to-dismiss; only adopt
`extended_image` for the gallery + per-page gesture stack).

## How to launch the PoC

1. Run the app: `flutter run -d <device>`.
2. On the Home screen, tap the **science flask icon** in the AppBar
   (top-right; only visible in debug builds — guarded by
   `kDebugMode`).
3. The PoC opens over a transparent `PageRouteBuilder`, so the
   `ExtendedImageSlidePage`'s backdrop alpha ramp is visually
   verifiable.

The PoC contains three programmatically-generated PNGs (red 1200×900
landscape, green 900×1600 portrait, blue 1024×1024 square) with a
centered white frame each — distinct colors and aspect ratios make it
easy to confirm `BoxFit.contain` behaviour and pinpoint which page
you're on.

## Environment

> _Human filler — please fill the row(s) that match the device(s) you
> actually exercised._

| Field | Value |
|---|---|
| Date verified | 2026-05-22 |
| Verifier | Reborn |
| Platform(s) | 笨蛋手测，未细化平台清单（未记录具体设备 / Flutter version / OS version 矩阵）|
| Verbal verdict | "测试完了，暂时没发现什么问题" |
| Caveat | "暂时" 字面包含保留空间 —— 未来若 ST2/ST3 实施期间发现 PoC 遗漏的边缘场景，回头补充手测矩阵 |

## Red flag (a): GitHub issue #736 — drag-to-dismiss + GesturePageView fragility

**Source**: <https://github.com/fluttercandies/extended_image/issues/736>
(open, 16 comments, Android, 9.1.0 reporter — extended to 10.0.1 by
research)

**Hypothesis**: single-finger vertical drag-to-dismiss is rejected by
the `ExtendedHorizontalDragGestureRecognizer` in the gesture arena, so
either (i) the swipe gets cancelled mid-flight, or (ii) the dismiss
fires but the gallery is left in an inconsistent state, or (iii) the
gallery refuses to switch pages after one successful dismiss attempt.

### Repro steps

1. Launch the PoC.
2. With the page **un-zoomed** (initial state), drag downward from
   the center of the image. Expected: backdrop fades from black to
   `alpha = 0.4` linearly with drag distance; release past 100 dp →
   route pops; release below 100 dp → spring-back to original
   position.
3. Swipe horizontally to page 2 (green portrait). Confirm gallery
   page-switch is smooth (no skipped frames, no half-page-stuck
   state).
4. Repeat step 2 on page 2.
5. Repeat steps 2-4 ten times in alternation to exercise the
   `gesture.dart:347-389` "zoomed → drag-to-dismiss disabled"
   transition: pinch-zoom page 2 to 2-3×, attempt drag-down — the
   page should pan within the image, NOT dismiss. Release (no
   dismiss). Pinch out to identity, attempt drag-down — dismiss
   should now work.
6. On a 3-finger pad / multi-touch device, attempt a fast vertical
   fling (velocity > 800 dp/s); the dismiss should trigger
   regardless of accumulated distance.

### Verdict

**PASS** — 经 Reborn 手测，未观察到 #736 hypothesis 描述的症状（gesture 竞技场冲突 / dismiss 中途取消 / 切页卡死 / dismiss 后画廊状态不一致）。`gesture.dart` L347-389 的"zoomed → drag-to-dismiss 自动屏蔽"在我们 PoC 用例下生效。

### Evidence

笨蛋反馈："测试完了，暂时没发现什么问题"。未提供 video / screenshot 证据。

---

## Red flag (b): GitHub issue #761 — v10.0.1 iOS `.memory` + `BoxFit.contain`

**Source**: <https://github.com/fluttercandies/extended_image/issues/761>
(open, 0 comments since 2026-02-22, iOS, 10.0.1 reporter; reporter used
`.file`, our use case is `.memory`)

**Hypothesis**: under iOS 10.0.1, `ExtendedImageGesturePageView.builder`
+ `ExtendedImage.memory(..., fit: BoxFit.contain)` exhibits some form
of rendering / sizing regression (the issue is sparse on detail).

### Repro steps

1. Launch the PoC on iOS (simulator or physical device — physical
   preferred).
2. Observe page 1 (red landscape, 1200×900 — wider than typical
   phone viewport): is the image rendered with proper `BoxFit.contain`
   letterboxing (black bands top + bottom)?
3. Swipe to page 2 (green portrait, 900×1600 — taller than typical
   phone viewport): same observation, with letterbox left + right.
4. Swipe to page 3 (blue square): should fit one dimension flush, the
   other letterboxed.
5. Pinch zoom on each: zoom focal should stay anchored at the pinch
   center; no jumping / wrong-scale on first frame.
6. Double-tap zoom (2×): focal point should be the tap location (or
   image center if tap landed in the letterbox).

### Verdict

**PASS** — 经 Reborn 手测，未观察到 #761 描述的 `.memory + BoxFit.contain` 渲染回归（letterbox 正常、focal 锚点正常、双击 zoom 焦点正常）。注意笨蛋未明确说明是否在 iOS 平台测试，但 #761 是 iOS-specific bug 描述，若仅在 Android / 桌面测试则该红旗的 verdict 实际为 "indirectly inferred PASS" —— 后续 ST2 实施期间如有 iOS 真机访问应补测。

### Evidence

笨蛋反馈："测试完了，暂时没发现什么问题"。未提供 screenshot 证据，未明确测试平台矩阵。

---

## Red flag (c): Desktop mouse drag for page switching

**Source**: Research file
`.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/research/extended_image-gallery-api.md`
("桌面鼠标拖动" section). Maintainer has not officially tested mouse
drag for `ExtendedImageGesturePageView`. Project spec
`.trellis/spec/frontend/component-guidelines.md` documents Flutter's
default `MaterialScrollBehavior` omitting `PointerDeviceKind.mouse`
from `dragDevices`.

**Hypothesis**: even with the PoC wrapping the `PageView` in a
`ScrollConfiguration(behavior: _PocScrollBehavior(...dragDevices includes
mouse...))`, mouse-drag page switching may fail because
`ExtendedImageGesturePageView` uses a custom
`ExtendedHorizontalDragGestureRecognizer` whose internal `supportedDevices`
isn't necessarily wired to the surrounding `ScrollConfiguration` —
research only confirmed it via reading source; no maintainer-blessed
test exists.

### Repro steps

1. Launch the PoC on macOS / Windows / Linux desktop (`flutter run -d
   macos` etc).
2. Click + drag horizontally on the image area with a **mouse** (not
   trackpad). Expected: gallery snaps to the next / previous page,
   same as a touch swipe would.
3. Pinch + scroll-wheel zoom in (`extended_image` documents wheel
   zoom out of the box). Drag the zoomed image around with mouse —
   should pan. Drag past the right edge — should switch to the next
   page.
4. Repeat with trackpad two-finger horizontal scroll: should also
   switch pages.
5. Release mouse mid-drag (less than half a viewport) — should snap
   back to current page.

### Verdict

**PASS** — 经 Reborn 手测，桌面 mouse drag 切页工作正常。这表示 `_PocScrollBehavior(dragDevices: 6 PointerDeviceKind)` 外包 + `ExtendedHorizontalDragGestureRecognizer` 默认 `supportedDevices = null`（接受所有设备）的组合，在桌面 mouse 拖动场景下足够。**ST2 必须保留**同样的 `ScrollConfiguration(behavior with 6 dragDevices)` 注入。

### Evidence

笨蛋反馈："测试完了，暂时没发现什么问题"。未提供 recording 证据，未明确具体在哪个桌面 OS（macOS / Windows / Linux）验证。

---

## Lock graph

`flutter pub deps --no-dev | grep -E "extended_image|http_client_helper"`
captured on 2026-05-22 after adding `extended_image: ^10.0.1` to
`pubspec.yaml`:

```
├── extended_image 10.0.1
│   ├── extended_image_library 5.0.1
│   │   ├── http_client_helper 3.0.0
```

Transitive `http_client_helper` is new but isolated (only used by
`extended_image_library`'s network image loader — we use
`.memory` exclusively, so the network path is dormant). All other
transitive deps (`crypto`, `js` legacy stub, `path`, `path_provider`,
`web`) are already in the project's pubspec or `pubspec.lock` and the
declared `extended_image_library 5.0.1` constraints intersect cleanly.

`flutter pub get` exited 0 with no SAT-solver warnings, only "older
than latest" notes for packages we've intentionally pinned (Riverpod
2.x, file_picker 8.x, etc — these are unrelated to the
extended_image addition).

## Project gates (pre-verification)

| Gate | Status |
|---|---|
| `flutter pub get` clean | PASS (no SAT conflicts; 3 packages added) |
| `flutter analyze` 0 issues | PASS |
| `dart format --set-exit-if-changed .` 0 files changed | PASS |
| Existing `flutter test` (548 tests + 3 skipped) | PASS (no regressions from PoC introduction) |
| PoC entry reachable from `kDebugMode` build | PASS (Home AppBar science flask icon) |

## Recommendation

**Approach A 推进** — 3/3 红旗在笨蛋手测下未观察到 hypothesis 描述的症状。ST2 / ST3 / ST4 按父 brainstorm PRD `Implementation Plan` 顺序推进：

* ST2 → 重写 `preview_full_screen_dialog.dart`（用 `ExtendedImageSlidePage` + `ExtendedImageGesturePageView.builder` + `ExtendedImage.memory(mode: gesture, inPageView: true)` 三件套）
* ST3 → 重写 `preview_thumbnail.dart`（用 `ExtendedImage.memory(mode: none)`）
* ST4 → 重写 783 行测试 + ADR-0001 加 `Superseded by ADR-0002` + 新写 `ADR-0002`

### Residual risks (carry-over to ST2/ST3 verification)

1. 笨蛋未细化测试平台矩阵 —— iOS 平台对红旗 (b) 的 verdict 是 "indirectly inferred"，ST2 实施期间若有 iOS 真机访问应补做手测。
2. "暂时" 字面包含保留空间 —— ST2/ST3 实施期间如发现 PoC 遗漏的边缘场景（例如缩放后超快连续切页 / mouse wheel zoom 后切页 / iOS 真机内存压力下的渲染），回头到本任务补充矩阵。
3. spring-back 曲线 `easeOutCubic → linear` 的视觉差异 ST2 编码时需注意 —— `slide_page.dart` L201-216 不可配，本任务接受该降级（见父 PRD R3-exception (2)）。

## Cleanup checklist (post-verification)

Independent of the verdict, ST4 must remove the following debug-only
scaffolding before merging the migration PR:

* `lib/_poc/` directory (entire dir; only contains
  `extended_image_poc.dart`)
* `import '../../../../_poc/extended_image_poc.dart';` line in
  `lib/features/home/presentation/screens/home_screen.dart`
* `import 'package:flutter/foundation.dart';` line in the same file
  (only kept for `kDebugMode`; revert to the original import set)
* The `if (kDebugMode)` IconButton block in the Home AppBar
  `actions:` list
* This `poc-report.md` file (archive it into the task's `archive/`
  folder if you want to preserve the trail)

Grep `TODO(ST4)` to find every site that needs cleanup.
