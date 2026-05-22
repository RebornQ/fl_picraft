# ST2 Migration — Tests Failing in `preview_full_screen_dialog_test.dart`

> **Generated**: `flutter test test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart` after the ST2 widget tree rewrite.
> **ST2 status**: All non-dialog tests pass (172 tests under `test/features/export/`, 298 under `test/features/{long_stitch,grid,image_import}/`); `flutter analyze` clean; `dart format` clean.
> **ST2 result**: 9 passed, 18 failed out of 27 in `preview_full_screen_dialog_test.dart` — **as expected** (the widget tree changed, the test bodies still target the old self-rolled `InteractiveViewer / PageView / _ImmersivePageScrollPhysics`).
> **Audience**: ST4 (`05-22-rewrite-tests-and-adrs`) consumes this list to rewrite the test cases.

## Surviving tests (9 — still PASS after the rewrite)

These tests don't touch any of the deleted symbols and pass against the new
three-piece kit. ST4 should **keep them green** (regressions in this group
would be a real bug, not a test rewrite need):

1. `PreviewFullScreenDialog tap on PreviewThumbnail opens the dialog`
2. `PreviewFullScreenDialog close button title and tooltip render`
3. `PreviewFullScreenDialog tapping the close button pops the dialog`
4. `PreviewFullScreenDialog — chrome (Step 2) chrome (AppBar) is visible by default on open`
5. `PreviewFullScreenDialog — chrome (Step 2) chrome auto-hides after 3 seconds`
6. `PreviewFullScreenDialog — chrome (Step 2) floating close button stays interactive after chrome auto-hides`
7. `PreviewFullScreenDialog — chrome (Step 2) AppBar leading slot is empty (no auto-injected back arrow)`
8. `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) single-image title shows "预览"`
9. `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) multi-image title shows "X / Y"`

## Failing tests (18 — ST4 must rewrite)

Grouped by the root-cause category. Each entry lists the test name, the
**deleted symbol** the assertion currently looks up, and the **suggested
replacement** under the `extended_image` three-piece kit.

### A. `InteractiveViewer`-targeted assertions (5 tests)

These tests look up `find.byType(InteractiveViewer)` and inspect properties
(`minScale`, `maxScale`, `boundaryMargin`, `constrained`, `transformationController`)
that no longer exist in the new widget tree.

| Test | Replace `InteractiveViewer` lookups with… |
|---|---|
| `PreviewFullScreenDialog dialog contains an InteractiveViewer` | `find.byType(ExtendedImage)` + inspect the live `ExtendedImageGestureState.gestureDetails.gestureConfig` to assert `minScale == 1.0` / `maxScale == kMaxScale`. |
| `PreviewFullScreenDialog InteractiveViewer.boundaryMargin is EdgeInsets.zero so pan is clamped to image-pixel bounds (see 05-22-limit-fullscreen-preview-pan-bounds)` | **Delete the test** — the M-α layout (`SizedBox.fromSize(renderedSize) + boundaryMargin: EdgeInsets.zero`) no longer exists. `extended_image` clamps to viewport edges by default; an equivalent assertion would inspect `state.gestureDetails.boundary` flags after pinning a zoom, but the spec contract has shifted (see ADR-0002). |
| `PreviewFullScreenDialog InteractiveViewer uses constrained:true (default) + Center + SizedBox(renderedSize) + Image(fit: fill) so the image is centred inside the viewport-sized child (M-α layout from 05-22-limit-fullscreen-preview-pan-bounds, after the L-β constrained:false attempt regressed centring due to Flutter's OverflowBox(topLeft) hard-coding)` | **Delete the test** — the M-α / L-β / OverflowBox saga is entirely irrelevant under `extended_image`. ADR-0002 should record this as "letterbox focal fallback eliminated; layout no longer rests on M-α". |
| `PreviewFullScreenDialog after a double-tap zoom + reset, the image remains centred — regression for the L-β attempt where constrained:false anchored the image at the viewport top-left corner` | Rewrite: drive a double-tap via `tester.tapAt` + advance the `AnimationController` clock; then drive a second double-tap to reset; then assert the rendered image rect (`tester.getRect(find.byType(ExtendedImage))`) is centred in the viewport. The "rendered size differs from viewport" sanity guard (lines 198–205 of the current test) should be preserved — keep the `runAsync(precacheImage)` priming since `extended_image` still relies on `ImageStream` resolution. |
| `PreviewFullScreenDialog pan beyond image-pixel edge is clamped: dragging twice in the same direction does not push translation past the boundary` | Rewrite as: pre-zoom the `ExtendedImage` via `state.handleScaleStart/Update` (or the public `state.gestureDetails`), drag, capture `state.gestureDetails.offset`, drag again, assert `offset` did not advance beyond the package's clamp. Caveat: `extended_image`'s clamp is **viewport-edge**, not image-pixel — the assertion magnitude may change. Cross-check with the package's `Boundary` flags exposed on `gestureDetails`. |

### B. `InteractiveViewer` chrome-toggle test (1 test)

| Test | Issue | Replacement |
|---|---|---|
| `PreviewFullScreenDialog — chrome (Step 2) single tap toggles chrome and resets the timer` | The test calls `tester.tap(find.byType(InteractiveViewer))`; `InteractiveViewer` no longer exists. | Replace with `tester.tap(find.byType(_PreviewPage))` — but `_PreviewPage` is private. Use `tester.tap(find.byType(ExtendedImage))` instead, OR pin the GestureDetector that wraps each page via `tester.tap(find.descendant(of: find.byType(ExtendedImage), matching: find.byType(GestureDetector)))`. The chrome-toggle wiring itself (`onTap: _toggleChrome` on the outer `GestureDetector` with `behavior: HitTestBehavior.translucent`) is preserved verbatim — only the finder needs updating. |

### C. `InteractiveViewer` gesture tests (4 tests)

These tests exercise the scale / pan / double-tap behavior. They need to be
rewritten against `ExtendedImageGestureState`'s public API
(`gestureDetails.totalScale`, `gestureDetails.offset`, `handleDoubleTap`).

| Test | Suggested rewrite |
|---|---|
| `PreviewFullScreenDialog — gestures (Step 3) InteractiveViewer.minScale == 1.0 and panEnabled == false at identity` | Find `ExtendedImage` via `find.byType(ExtendedImage)`, then `tester.widget<ExtendedImage>(...).initGestureConfigHandler!(/* a dummy ExtendedImageState — see package's `GestureConfig` constructor for ergonomics */)` and assert `minScale == 1.0` + `maxScale == kMaxScale`. NOTE: "panEnabled at identity" has no equivalent — `extended_image` always allows pan but the SlidePage routes single-finger pan to drag-to-dismiss when un-zoomed (see `gesture.dart:347-389`). Replace the `panEnabled == false at identity` assertion with: drag vertically while un-zoomed, assert it pops the dialog (route to `ExtendedImageSlidePage`); pre-zoom, drag vertically, assert dialog stays. |
| `PreviewFullScreenDialog — gestures (Step 3) double-tap on the image animates the controller up to ~2.0× scale` | Drive `tester.tapAt(viewerCenter)` × 2 with appropriate timing; advance the test clock past `kZoomAnimationDuration`; then grab `final pageState = tester.state<_PreviewPageState>(find.byType(_PreviewPage))` — **but `_PreviewPage` is private**, so use `tester.state<State>(find.byType(ExtendedImage)).gestureDetails.totalScale` (cast via `ExtendedImageGestureState`). Assert it closes to `kDoubleTapZoomScale = 2.0`. |
| `PreviewFullScreenDialog — gestures (Step 3) double-tap while zoomed resets the matrix to identity` | Pre-zoom the `ExtendedImageGestureState` to 2.0× via its public API (or trigger one double-tap and let it animate). Drive a second double-tap. Assert `gestureDetails.totalScale == 1.0`. |
| `PreviewFullScreenDialog — gestures (Step 3) double-tap focal falls back to image centre when tap lands in letterbox` | **Delete or weaken this test** — `extended_image` clamps the double-tap focal point internally (see `gesture.dart` `handleDoubleTap` — the `doubleTapPosition` is clamped against `state.gestureDetails.boundary` automatically). The test's specific letterbox-fallback semantics no longer apply. ST4 might keep a smoke version: "double-tap in letterbox does not push the image out of view" — but the precise translation math from the current test no longer holds. |

### D. `PageView` / `PageScrollPhysics` tests (5 tests)

These tests look up `find.byType(PageView)` and / or assert the physics class.
The new tree uses `ExtendedImageGesturePageView.builder` whose internals are
not `PageView` at all (it embeds an `ExtendedImageGesturePageView` widget
with its own custom recognizer stack).

| Test | Suggested rewrite |
|---|---|
| `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) multi-image dialog renders a PageView` | Replace `find.byType(PageView)` with `find.byType(ExtendedImageGesturePageView)`. |
| `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) PageView uses immersive physics that is a PageScrollPhysics` | **Delete the test** — `_ImmersivePageScrollPhysics` no longer exists; physics is owned internally by `extended_image`. ADR-0002 should note "physics ownership migrated to upstream". |
| `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) swiping horizontally while un-zoomed advances to the next page` | Rewrite finder: `tester.fling(find.byType(ExtendedImageGesturePageView), const Offset(-400, 0), 1200)`; assertion (`expect(find.text('2 / 3'), findsOneWidget)`) unchanged. |
| `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) vertical drag exceeding threshold pops the dialog` | Rewrite finder: `tester.drag(find.byType(ExtendedImage), const Offset(0, 200))`. The threshold (`kDragToDismissDistance = 100`) and pop assertion are preserved by `_slideEndHandler`. |
| `PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4) vertical drag below threshold snaps back and keeps the dialog open` | Same as above: rewrite finder; the spring-back (now linear, not `easeOutCubic`) is owned by `ExtendedImageSlidePage`. Adjust the wait duration if necessary — `ExtendedImageSlidePage` uses `resetPageDuration: const Duration(milliseconds: 500)` by default. |

### E. Regression-block `ScrollConfiguration` / mouse-drag tests (3 tests)

These tests probe the `ScrollConfiguration` ancestor of `PageView`.
`_ImmersiveScrollBehavior` is preserved, but the inner widget changed.

| Test | Suggested rewrite |
|---|---|
| `PreviewFullScreenDialog — regressions (desktop mouse + zoomed pan) PageView is wrapped in a ScrollConfiguration whose dragDevices include mouse / trackpad (desktop / web mouse-drag support)` | Replace `find.byType(PageView)` with `find.byType(ExtendedImageGesturePageView)` in the `find.ancestor` chain. The `_ImmersiveScrollBehavior` assertion (mouse / trackpad in `dragDevices`) is preserved. |
| `PreviewFullScreenDialog — regressions (desktop mouse + zoomed pan) touch fling on PageView still advances pages (regression check that the custom ScrollConfiguration did not break the default touch path)` | Same finder swap (`ExtendedImageGesturePageView`); same fling + assertion. |
| `PreviewFullScreenDialog — regressions (desktop mouse + zoomed pan) single-finger pan after double-tap zoom moves the matrix (outer vertical-drag recognizer is not in the arena while zoomed)` | Pre-zoom via `ExtendedImageGestureState` API, capture `gestureDetails.offset` before / after a vertical drag. Assert offset changed AND dialog stayed open. The bug guard (un-zoomed vertical drag → dismiss; zoomed vertical drag → pan) is shifted entirely into `extended_image`'s `gesture.dart:347-389` — but a smoke test that confirms the behavior at the integration layer is still valuable. |

## Notes for ST4

1. **Setup helper to expose `_PreviewPageState`**: many of the rewrites would
   benefit from a way to grab the live `ExtendedImageGestureState`. Two paths:
   - Add a `@visibleForTesting` getter on `_PreviewPage` that exposes the
     gesture state via a `GlobalKey<ExtendedImageGestureState>`. Cleanest, but
     adds production surface.
   - Use `tester.state<State>(find.byType(ExtendedImage))` and cast to
     `ExtendedImageGestureState`. Less invasive; works because
     `ExtendedImage` with `mode: ExtendedImageMode.gesture` creates an
     `ExtendedImageGestureState` internally.
2. **`MemoryImage` decode priming**: continue to use
   `tester.runAsync(() => precacheImage(MemoryImage(bytes), element))` for
   any test that depends on intrinsic image size. `extended_image` still
   resolves via `ImageStream` under the hood.
3. **Animations**: `extended_image` uses linear `AnimationController` for
   spring-back (no `CurvedAnimation`). When advancing timers, advance by
   `resetPageDuration = 500ms` (not the prior `kDragSnapBackDuration =
   250ms`).
4. **Symbols still in the test file that ST4 must clean up**:
   - `_dialogHarness` and `_multiDialogHarness` helpers should be unchanged
     (they just wrap the public `PreviewFullScreenDialog`). The shared
     `_smallPng` is fine.
   - `import 'package:flutter/gestures.dart'` is still needed (for
     `PointerDeviceKind` in section E tests).
   - Drop `import 'dart:typed_data'` if unused.
