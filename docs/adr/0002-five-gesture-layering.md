# ADR-0002: Five-gesture layering inside the fullscreen preview dialog

**Date**: 2026-05-22
**Status**: Accepted
**Context task**: `.trellis/tasks/05-22-export-preview-fullscreen-immersive/`
**Related**: [ADR-0001](./0001-immersive-page-scroll-physics.md)

---

## Context

The fullscreen preview dialog (`PreviewFullScreenDialog`) supports five concurrent gestures:

| # | Gesture | Purpose | Constraint |
|---|---------|---------|-----------|
| ① | Single tap | Toggle chrome (AppBar) visibility | Resets the 3-second auto-hide timer |
| ② | Double tap | Zoom in to 2.0x at tap point / reset to identity | Must capture `localPosition` (TapDownDetails) |
| ③ | Two-finger pinch + zoomed-state single-finger pan | Scale + pan via InteractiveViewer | Two recognizers internal to InteractiveViewer |
| ④ | Horizontal drag | Page swipe (un-zoomed) / pan + edge-bleed-to-page (zoomed) | Routed via custom `_ImmersivePageScrollPhysics` per ADR-0001 |
| ⑤ | Vertical drag (downward) | Drag-to-dismiss the dialog | Only enabled when current page `scale ≈ 1.0` |

**Hard Flutter constraint**: a single `GestureDetector` cannot declare both `onHorizontalDrag*` and `onVerticalDrag*` callbacks — Flutter asserts at runtime to avoid ambiguous arena resolution. So we cannot put gestures ④ and ⑤ on the same widget.

We need a layout that:
1. routes each gesture to the right consumer
2. lets the gesture arena resolve conflicts predictably
3. respects the "only when un-zoomed" guards (R6: vertical drag → dismiss is gated by zoom state)

## Decision

Five layers, each owning one or two gestures:

```
Dialog root
└─ GestureDetector(onVerticalDragStart/Update/End)   ← gesture ⑤
   ├─ enabled iff currentZoomed == false              (vertical drag-to-dismiss)
   │
   └─ Stack
      ├─ PageView(physics: _ImmersivePageScrollPhysics) ← gesture ④
      │  └─ _PreviewPage(itemIndex: i)                   (horizontal — page swipe + edge bleed)
      │     └─ GestureDetector(onTap, onDoubleTap, onDoubleTapDown)  ← gestures ① + ②
      │        └─ InteractiveViewer(transformationController: ...)    ← gesture ③
      │           └─ Image.memory(...)
      │
      └─ Positioned(常驻 X close button)                  (always tappable)
```

Each layer's responsibility is **single-purpose**:

* **Outer `GestureDetector`**: only vertical drag, guarded by `currentZoomed`. When `currentZoomed == true`, the recognizer is disabled (callbacks null) and the gesture is never claimed — so the same vertical drag falls through to InteractiveViewer for pan
* **PageView**: only horizontal drag (its own internal recognizer); routed via the custom physics from ADR-0001
* **Inner `GestureDetector`** (per page): only tap recognizers (single + double, mutually exclusive within `GestureDetector`); these never conflict with drag recognizers above
* **InteractiveViewer**: handles two-finger pinch + zoomed-state pan via its internal `ScaleGestureRecognizer`

## Arena resolution analysis

For each gesture pattern, Flutter's gesture arena resolves to a single winner:

| User input | Winner | Why |
|------------|--------|-----|
| Tap (no drag) | Inner `TapGestureRecognizer` | Only recognizer that accepts no movement |
| Double tap | Inner `DoubleTapGestureRecognizer` | Two taps within `kDoubleTapTimeout` |
| Pure horizontal drag | PageView's `HorizontalDragGestureRecognizer` | Vertical-drag and tap recognizers disqualify at first non-vertical / non-zero movement |
| Pure vertical drag (un-zoomed) | Outer `VerticalDragGestureRecognizer` | Horizontal-drag and tap recognizers disqualify; vertical is enabled |
| Pure vertical drag (zoomed) | InteractiveViewer's `ScaleGestureRecognizer` | Outer vertical is disabled (callbacks null), so it never claims — scale recognizer accepts single-finger pan when `scale > 1.0` |
| Two-finger pinch | InteractiveViewer's `ScaleGestureRecognizer` | Tap & drag recognizers disqualify on second pointer down |
| Diagonal drag ≈ 45° | First recognizer to exceed `kPanSlop` (18 dp) | Non-deterministic — see Risks below |

## Risks and accepted edge cases

### Risk 1: Diagonal drag ambiguity

A user dragging at exactly 45° will hit `kPanSlop` simultaneously on horizontal and vertical recognizers. Flutter resolves by first-to-arena-victory (essentially a microsecond race).

**Accepted**: Real-world users don't drag exactly 45°. The probability that this matters in practice is near zero. Documenting it here so a future debugger doesn't assume it's a bug.

### Risk 2: Drag-to-dismiss starting while zoomed, then user pinches out

User scenario:
1. Image is zoomed to 2.0x
2. User pinches out to scale = 1.0 (single-finger pan would normally still work momentarily)
3. User immediately starts vertical drag

Our `currentZoomed` flag updates via `TransformationController` listener, which fires synchronously per matrix change. By the time the vertical drag exceeds slop, `currentZoomed` should already be `false` and outer recognizer is enabled. **Accepted**: tested via state-transition test.

### Risk 3: Drag-to-dismiss interrupting a horizontal page swipe

User starts a near-horizontal-but-slightly-vertical drag. If the PageView wins the arena (more likely for actual horizontal intent), the vertical recognizer never claims. If the vertical recognizer wins (truly vertical), the PageView never starts. The "interruption mid-swipe" scenario doesn't physically exist because a gesture has exactly one winner.

### Risk 4: Inner tap eating fast taps during chrome auto-hide animation

After the 3-second timer fires and AppBar starts fading, a fast tap before the fade completes will toggle `_chromeVisible` back to true and reset the timer. The user perceives this as "tapping to keep chrome visible". **Accepted** — this is desired behavior.

## Implementation notes

### Outer `VerticalDragGestureRecognizer` must be disabled via `null` callbacks, not `return`-in-callback

A subtle but load-bearing point about how the "only when un-zoomed" guard is implemented for gesture ⑤:

`GestureDetector` decides at **build time** whether to register a given `*GestureRecognizer` by looking at whether the corresponding callback (`onVerticalDragStart`, `onVerticalDragUpdate`, `onVerticalDragEnd`) is non-null. Once a recognizer is registered, it **enters the gesture arena** for every pointer-down on its hit region, and — for vertical drag — wins the arena as soon as the vertical movement crosses `kTouchSlop` (≈ 18 dp).

If the guard is implemented inside the callback body (`if (zoomed) return`), the recognizer is **already in the arena** and has **already won** by the time the callback fires. The pointer events for the rest of the gesture are then consumed exclusively by that recognizer; InteractiveViewer's `ScaleGestureRecognizer` never sees them, so single-finger pan on a zoomed image is silently dead.

**Correct shape** (build-time guard):

```dart
GestureDetector(
  onVerticalDragStart: _currentZoomed ? null : _onVerticalDragStart,
  onVerticalDragUpdate: _currentZoomed ? null : _onVerticalDragUpdate,
  onVerticalDragEnd: _currentZoomed ? null : _onVerticalDragEnd,
  behavior: HitTestBehavior.deferToChild,
  child: ...,
)
```

Because `_currentZoomed` must drive a rebuild for this to take effect, the dialog state mirrors `_gestureState.value.zoomed` (the `ValueNotifier` consumed by `_ImmersivePageScrollPhysics`) into a `setState`-driven `bool _currentZoomed` field. The `ValueNotifier` cannot drive a rebuild on its own — it's read by `ScrollPhysics`, which has no widget tree — so the two state representations co-exist by design.

### Desktop / web mouse drag on the PageView requires a custom `ScrollBehavior`

Flutter's default `MaterialScrollBehavior.dragDevices` set excludes `PointerDeviceKind.mouse`, so on macOS / Windows / Linux / web a user with a mouse cannot drag the multi-image gallery's PageView to switch pages — the gesture is filtered out before any recognizer sees it.

We install a private `_ImmersiveScrollBehavior extends MaterialScrollBehavior` that overrides `dragDevices` to include all six device kinds (`touch`, `mouse`, `stylus`, `trackpad`, `invertedStylus`, `unknown`), and wrap the PageView in a `ScrollConfiguration(behavior: const _ImmersiveScrollBehavior(), child: PageView.builder(...))`. The ScrollConfiguration nearest to the Scrollable wins, so even though the surrounding `MaterialApp` has its own ScrollConfiguration, the closer override takes effect.

This is the same pitfall captured in `.trellis/spec/frontend/component-guidelines.md` → "Gotcha: Flutter 桌面端 PageView / ListView 默认不响应鼠标拖动".

## Alternatives considered

### A. `RawGestureDetector` with custom `GestureRecognizerFactory`

Hand-roll the entire arena. Total control, no Flutter quirks. **Rejected** — 200+ lines of recognizer plumbing for an outcome we can achieve with composition. The composition path is simpler to read and debug.

### B. Single nested `GestureDetector(onPan*)` (instead of split horizontal/vertical)

Use `onPan*` callbacks and manually inspect `details.delta` to dispatch to horizontal-swipe or vertical-dismiss logic. **Rejected** — `onPan*` is a single recognizer; it competes against tap and scale recognizers as one unit, but we want PageView to remain independently arbitrable for horizontal-only intent (so it can use its own physics from ADR-0001). Splitting horizontal (PageView) and vertical (outer GestureDetector) lets the physics layer behave naturally.

### C. Wrap InteractiveViewer in its own GestureDetector to intercept everything

Hide InteractiveViewer behind a translucent gesture layer that fans gestures out to PageView / dismiss / zoom logic manually. **Rejected** — re-implements behavior Flutter already provides via the recognizer arena.

## Consequences

### Positive

* Each gesture has exactly one owner — easy to reason about
* No re-implementation of Flutter built-ins (scale, tap, drag recognizers all official)
* Adding a 6th gesture later (e.g. long-press for context menu) only adds one layer

### Negative

* Five layers of widgets — the widget tree gets deep around the gesture surface. Mitigated by the inline tree diagram above
* Outer `GestureDetector` needs `enabled`-style guard via `null`-ing callbacks when zoomed — slightly awkward Flutter API but standard practice

### Neutral

* Test coverage requires gesture-sequence tests using `WidgetTester.dragFrom + drag + pumpFrames`. Authoring is mechanical once the pattern is established.

## Validation criteria

* Tap on image → AppBar toggles, timer resets
* Double-tap on image → zoom anim plays, lands at 2.0x with focal at tap point (or image center if tap landed in BoxFit.contain letterbox)
* Pinch on image → InteractiveViewer scales
* Horizontal drag (un-zoomed) → page swipes
* Horizontal drag (zoomed, mid-image) → InteractiveViewer pans, no page change
* Horizontal drag (zoomed, clamped + outward) → page bleed-through (ADR-0001)
* Vertical down drag (un-zoomed) → background fades, body translates, release > threshold pops dialog
* Vertical down drag (zoomed) → InteractiveViewer pans, dialog stays open
* Tap on floating X (any zoom state, any chrome state) → pops dialog

## References

* ADR-0001: `0001-immersive-page-scroll-physics.md` — the horizontal half of this puzzle
* PRD: `.trellis/tasks/05-22-export-preview-fullscreen-immersive/prd.md` (Requirements R1–R6)
* Flutter gesture arena: https://flutter.dev/learn-more/gestures
