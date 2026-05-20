# Research: macOS native window management + Settings menu wiring (Flutter macOS app)

- **Query**: NSWindow frame persistence (manual vs autosave), HiDPI handling, multi-screen safety, `minSize` vs `contentMinSize`, MainMenu.xib wiring for `Settings…` → IBAction on `AppDelegate`, Swift↔Flutter `FlutterMethodChannel` bridge, macOS 13+ HIG rename, edge cases.
- **Scope**: external (Apple developer docs + HIG + Flutter macOS embedder docs)
- **Date**: 2026-05-20
- **Target task**: `.trellis/tasks/05-20-desktop-window-mgmt-and-menu`

---

## Executive summary

1. **Use `frameAutosaveName`, not manual UserDefaults round-trip.** It is a one-line opt-in to AppKit-managed save/restore that handles user resizes/moves, multi-screen reattach, and is HiDPI-clean by construction (points, not pixels). Manual `NSStringFromRect`/`NSRectFromString` is the documented fallback if we need bespoke logic (e.g. injecting an 80% default on first launch).
2. **Set `contentMinSize`, not `minSize`.** `contentMinSize` constrains the content area (excludes title bar), takes precedence over `minSize`, and matches the user-facing expectation of "minimum 1280×800 usable canvas". `minSize` includes the title bar (~28 pt overhead) and gives confusing results.
3. **Apple HIG (macOS 13+) lists the App-menu entry as "Settings…" — with U+2026 ellipsis, ⌘,.** "Preferences…" is a legacy spelling; rename the menu item literal in `MainMenu.xib`. There is no system-provided `openSettings:` selector outside SwiftUI's `OpenSettingsAction` (macOS 14+), so we must declare our own `@IBAction func openSettings(_:)` on `AppDelegate` and wire the XIB connection by hand.
4. **`MainMenu.xib` is loaded before `applicationWillFinishLaunching`.** The right place to construct the `FlutterMethodChannel` is `MainFlutterWindow.awakeFromNib` (after `FlutterViewController` is instantiated), using `controller.engine.binaryMessenger`. The right place to *invoke* it is the `AppDelegate.openSettings(_:)` IBAction, which needs a strong reference to the channel (or a tiny singleton).
5. **Save on `applicationWillTerminate(_:)`, with `windowWillClose(_:)` as a backup.** Both call sites read the same `mainFlutterWindow.frame`. Apple explicitly notes `applicationWillTerminate` is skipped during *sudden termination*, but a stock Flutter macOS app does not opt into sudden termination, so this is the canonical hook. For paranoia, also save on `windowWillClose` (always fires before `applicationWillTerminate` on Cmd+Q / X click).

---

## Recommended implementation outline (Swift)

There are two viable strategies. We recommend **Strategy A** (frameAutosaveName) because it's the most native, the least code, and is what Apple's own apps use. Strategy B (manual round-trip) is documented for completeness and matches the current PRD draft.

### Strategy A — `frameAutosaveName` (recommended)

```swift
// macos/Runner/MainFlutterWindow.swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Bridge owns the FlutterMethodChannel; exposed for AppDelegate.
  var menuBridge: MenuChannelBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // --- Minimum size: 1280x800 in content (logical) points ---
    // contentMinSize constrains the content area (no title bar) and
    // takes precedence over minSize. This is what the user perceives
    // as "minimum usable canvas".
    self.contentMinSize = NSSize(width: 1280, height: 800)

    // --- Default 80% of visible work area on first launch ---
    // visibleFrame excludes the dock, menu bar, and (on M-series notch
    // MacBooks) the camera housing area.
    if let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first {
      let visible = screen.visibleFrame
      let w = floor(visible.width  * 0.80)
      let h = floor(visible.height * 0.80)
      // Respect our own min.
      let width  = max(w, 1280)
      let height = max(h, 800)
      let x = visible.minX + (visible.width  - width)  / 2
      let y = visible.minY + (visible.height - height) / 2
      // setFrame(_:display:) is NOT constrained by minSize (docs say so
      // explicitly), so we can size precisely.
      self.setFrame(NSRect(x: x, y: y, width: width, height: height),
                    display: true)
    }

    // --- Autosave: AppKit reads/writes "NSWindow Frame fl_picraft.main"
    // in UserDefaults.standard automatically on user resize/move and at
    // app launch. If the autosaved value is present at -setFrameAutosaveName,
    // AppKit immediately repositions the window from the saved value,
    // overriding the default we just set. That's exactly what we want.
    // Returns false only if another live window already owns the name.
    _ = self.setFrameAutosaveName("fl_picraft.main")

    RegisterGeneratedPlugins(registry: flutterViewController)

    // --- Wire the Flutter MethodChannel for native → Dart menu events ---
    let bridge = MenuChannelBridge(
      messenger: flutterViewController.engine.binaryMessenger
    )
    self.menuBridge = bridge
    (NSApp.delegate as? AppDelegate)?.menuBridge = bridge

    super.awakeFromNib()
  }
}
```

```swift
// macos/Runner/MenuChannelBridge.swift  (new file)
import Cocoa
import FlutterMacOS

/// Thin Swift wrapper around the menu MethodChannel.
/// Owned by MainFlutterWindow; referenced by AppDelegate so menu IBActions
/// can fire invokeMethod without re-instantiating the channel.
final class MenuChannelBridge {
  static let channelName = "app.fl_picraft/menu"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    // Optional: also accept Dart → native pings (e.g. for "is settings open?")
    self.channel.setMethodCallHandler { call, result in
      // Currently no native-side handlers needed; reply unimplemented.
      result(FlutterMethodNotImplemented)
    }
  }

  /// Native → Dart: tell Flutter to navigate to /settings.
  func openSettings() {
    channel.invokeMethod("openSettings", arguments: nil)
  }
}
```

```swift
// macos/Runner/AppDelegate.swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Set by MainFlutterWindow.awakeFromNib once the Flutter engine is up.
  var menuBridge: MenuChannelBridge?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Wired from MainMenu.xib: App menu → "Settings…" (⌘,).
  /// The `_ sender:` parameter type must be `Any?` so it matches both
  /// NSMenuItem (XIB connection) and first-responder forwarding.
  @IBAction func openSettings(_ sender: Any?) {
    // Idempotency / "already on /settings" is handled on the Dart side;
    // the native side just fires the intent.
    menuBridge?.openSettings()
  }
}
```

XIB change (replace the orphan `Preferences…` line with a Settings… line that has a `<connections>` element wired to `AppDelegate.openSettings:`):

```xml
<!-- macos/Runner/Base.lproj/MainMenu.xib (excerpt) -->
<menuItem title="Settings…" keyEquivalent="," id="BOF-NM-1cW">
    <connections>
        <action selector="openSettings:" target="Voe-Tx-rLC" id="set-1-aci"/>
    </connections>
</menuItem>
```

Notes on the XIB diff:
- `title` literal changes from `Preferences…` to `Settings…` (U+2026 HORIZONTAL ELLIPSIS, single char — not three periods).
- `target="Voe-Tx-rLC"` is the existing AppDelegate XIB id already in this file (line 16 of MainMenu.xib).
- `id="set-1-aci"` is a fresh unique XIB id; pick anything not already in the file.
- `<connections>` siblings should be inserted *before* the closing `</menuItem>` tag.
- Do NOT add `target="-1"` (First Responder) — that delegates to the responder chain and we'd then need to implement `openSettings:` somewhere that the chain reaches. Direct AppDelegate is simpler.

Dart side (sketch — implementation is owned by another file in the task):

```dart
// lib/core/native/menu_channel.dart  (sketch only)
import 'package:flutter/services.dart';

class MenuChannel {
  static const _channel = MethodChannel('app.fl_picraft/menu');

  static void bind({required void Function() onOpenSettings}) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openSettings':
          onOpenSettings();
          return null;
        default:
          throw MissingPluginException();
      }
    });
  }
}
```

### Strategy B — manual `UserDefaults` round-trip

Use this only if we want to inject custom validation (e.g. "force snap to default if saved rect is off-screen") that `frameAutosaveName` won't do for us.

```swift
// macos/Runner/MainFlutterWindow.swift  (alternate body)
override func awakeFromNib() {
  let flutterViewController = FlutterViewController()
  self.contentViewController = flutterViewController
  self.contentMinSize = NSSize(width: 1280, height: 800)

  let savedFrame = WindowFramePersistence.load()
  if let f = savedFrame, isFrameOnScreen(f) {
    self.setFrame(f, display: true)
  } else {
    self.setFrame(defaultEightyPercentFrame(), display: true)
  }

  RegisterGeneratedPlugins(registry: flutterViewController)
  // ... menu bridge as in Strategy A ...
  super.awakeFromNib()
}

private func defaultEightyPercentFrame() -> NSRect {
  let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first!
  let v = screen.visibleFrame
  let w = max(floor(v.width  * 0.80), 1280)
  let h = max(floor(v.height * 0.80), 800)
  return NSRect(x: v.minX + (v.width  - w) / 2,
                y: v.minY + (v.height - h) / 2,
                width: w, height: h)
}

private func isFrameOnScreen(_ frame: NSRect) -> Bool {
  // Require ≥120pt intersection with at least one currently attached
  // screen's visibleFrame. Pure point containment is too strict
  // (multi-monitor users routinely straddle edges).
  for screen in NSScreen.screens {
    let inter = screen.visibleFrame.intersection(frame)
    if inter.width > 120 && inter.height > 120 { return true }
  }
  return false
}
```

```swift
// macos/Runner/WindowFramePersistence.swift  (new file, Strategy B only)
import Cocoa

enum WindowFramePersistence {
  private static let key = "fl_picraft.mainWindowFrame"

  static func load() -> NSRect? {
    guard let raw = UserDefaults.standard.string(forKey: key),
          !raw.isEmpty else { return nil }
    let r = NSRectFromString(raw)
    // NSRectFromString returns NSZeroRect for unparseable input.
    if r.width <= 0 || r.height <= 0 { return nil }
    return r
  }

  static func save(_ frame: NSRect) {
    UserDefaults.standard.set(NSStringFromRect(frame), forKey: key)
  }
}
```

Save hook (Strategy B; install in `AppDelegate`):

```swift
// macos/Runner/AppDelegate.swift  (Strategy B additions)
override func applicationWillTerminate(_ notification: Notification) {
  if let win = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
    WindowFramePersistence.save(win.frame)
  }
  super.applicationWillTerminate(notification)
}
```

---

## Decisions & citations

| Topic | Decision | Citation |
|---|---|---|
| Frame persistence | `frameAutosaveName` (Strategy A) | [`setFrameAutosaveName(_:)`](https://developer.apple.com/documentation/appkit/nswindow/setframeautosavename(_:)) / [`saveFrame(usingName:)`](https://developer.apple.com/documentation/appkit/nswindow/saveframe(usingname:)) / [`setFrameUsingName(_:)`](https://developer.apple.com/documentation/appkit/nswindow/setframeusingname(_:)) — Apple stores the frame under the default key `NSWindow Frame <name>` in `UserDefaults.standard`. |
| Manual rect serialization (fallback) | `NSStringFromRect` / `NSRectFromString` | [`NSStringFromRect(_:)`](https://developer.apple.com/documentation/foundation/nsstringfromrect(_:)) returns `"{{x, y}, {w, h}}"`. [`NSRectFromString(_:)`](https://developer.apple.com/documentation/foundation/nsrectfromstring(_:)) parses it back; on parse failure returns `NSZeroRect`. |
| Min size | `contentMinSize = NSSize(1280, 800)` (NOT `minSize`) | [`contentMinSize`](https://developer.apple.com/documentation/appkit/nswindow/contentminsize): "the minimum size of the window's content view … This method takes precedence over the `minSize` property." [`minSize`](https://developer.apple.com/documentation/appkit/nswindow/minsize): "the minimum size to which the window's frame (including its title bar) can be sized." |
| 80% default | `NSScreen.visibleFrame * 0.80`, centered | [`visibleFrame`](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe): "defines the portion of the screen in which it is currently safe to draw your app's content … does not include the area currently occupied by the dock and menu bar … does not include the bezel [notch]." |
| Which screen on first launch | `self.screen ?? NSScreen.main ?? NSScreen.screens.first` | [`NSScreen.main`](https://developer.apple.com/documentation/appkit/nsscreen/main) "returns the screen object containing the window with the keyboard focus … is not necessarily the same screen that contains the menu bar." [`NSScreen.screens`](https://developer.apple.com/documentation/appkit/nsscreen/screens): index 0 == primary (menu bar) screen. |
| Set frame ignores minSize | `setFrame(_:display:)` is the right setter when restoring | [`setFrame(_:display:)`](https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:)) — `minSize` docs note: "The minimum size constraint is enforced for resizing by the user as well as for the setFrame... methods **other than** `setFrame(_:display:)` and `setFrame(_:display:animate:)`." |
| Save hook | `applicationWillTerminate(_:)` + `windowWillClose(_:)` belt-and-braces | [`applicationWillTerminate(_:)`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationwillterminate(_:)) "use this method to perform any final cleanup before the app terminates … this method isn't called during sudden termination of an app." [`windowWillClose(_:)`](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillclose(_:)) fires before the window's `dealloc`. |
| Pre-launch hook | `applicationWillFinishLaunching(_:)` runs *before* windows are shown but XIB is already loaded | [`applicationWillFinishLaunching(_:)`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationwillfinishlaunching(_:)) "tells the delegate that the app's initialization is about to complete." |
| Multi-screen change detection | observe `NSApplication.didChangeScreenParametersNotification` | [`didChangeScreenParametersNotification`](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification) "Posted when the configuration of the displays attached to the computer is changed." |
| Settings rename | App menu literal = "Settings…" (U+2026), keyEquivalent="," | [HIG → The menu bar → App menu](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#App-menu) lists the standard App-menu entry as **`Settings…`** with "Opens your settings window, or your app's page in iPadOS Settings." This is the macOS 13+ convention; Xcode 14+ templates ship XIBs using `Settings…`. Older templates (and our current XIB, generated by Flutter create) still emit `Preferences…`. |
| Selector | `openSettings:` on AppDelegate (custom IBAction) | The SwiftUI [`Settings` scene](https://developer.apple.com/documentation/swiftui/settings) (macOS 11+) and [`OpenSettingsAction`](https://developer.apple.com/documentation/swiftui/opensettingsaction) (macOS 14+) are **SwiftUI-only**. AppKit/XIB apps need a hand-rolled IBAction. Name `openSettings:` matches Apple's SwiftUI convention but is in our own namespace. |
| MethodChannel construction | `FlutterMethodChannel(name:binaryMessenger:)` against `controller.engine.binaryMessenger` | [Flutter macOS embedder — `FlutterMethodChannel`](https://api.flutter.dev/macos-embedder/interface_flutter_method_channel.html), [`FlutterViewController.engine`](https://api.flutter.dev/macos-embedder/interface_flutter_view_controller.html), [`FlutterEngine.binaryMessenger`](https://api.flutter.dev/macos-embedder/interface_flutter_engine.html#a14598e418b7c17fd871c08972f247aa6). |
| Channel name | `app.fl_picraft/menu` | Flutter docs convention: ["prefix the channel name with a unique 'domain prefix', for example: `samples.flutter.dev/battery`"](https://docs.flutter.dev/platform-integration/platform-channels#example-client). We use the reverse-DNS-ish `app.fl_picraft/<feature>` to leave room for future channels (`app.fl_picraft/window`, etc.) |
| XIB action target | `target="Voe-Tx-rLC"` (existing AppDelegate xib id), NOT `-1` (First Responder) | [Cocoa Nibs guide — Action connections](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingResources/CocoaNibs/CocoaNibs.html): "In OS X, the nib-loading code uses the source object's setTarget: and setAction: methods … If the target is nil, the action is handled by the responder chain." Direct target sidesteps the chain. |

---

## Edge cases & gotchas

### E1. First-launch UserDefaults miss

- **Strategy A**: `setFrameAutosaveName` returns `false` if the name is already in use by another live window, and is a no-op (for restoration) if the key isn't in defaults yet. We must `setFrame(...)` to our 80% default *before* calling `setFrameAutosaveName(...)` so that AppKit's "restore-or-leave-current" logic falls back to our default on first launch. Verified pattern: set frame → set autosave name.
- **Strategy B**: `NSRectFromString` returns `NSZeroRect` for missing/garbled input, so the `r.width <= 0` guard covers nil + corrupt cases identically. No throw, no crash.

### E2. Saved frame on a disconnected display (multi-monitor unplug, dock undock)

- **Strategy A**: AppKit *does* re-validate against current screens at restoration. If the autosaved frame is entirely off-screen, the system constrains it to the nearest visible screen (in practice: clamps origin so the title bar is visible). This is documented behavior of `constrainFrameRect(_:to:)`, which is called from the autosave path.
- **Strategy B**: Implement `isFrameOnScreen(_:)` explicitly (see Strategy B sample). Use a non-zero intersection threshold (≥120 pt × 120 pt) — pure rect containment is too strict for users who deliberately straddle two monitors.
- Both strategies should also observe `NSApplication.didChangeScreenParametersNotification` at runtime if we want to re-clamp a window that became off-screen during the session (out of scope for this task per current AC; just note it).

### E3. HiDPI / Retina migration

- `NSWindow.frame` and `NSScreen.visibleFrame` are both in **points** (logical), not pixels. A frame saved on a 220-ppi MacBook Pro and reopened on a 96-ppi external display restores to the *same point size* — the visual size is the same in screen-real-estate terms. There is no scale-factor conversion to do.
- Caveat: the *backing* pixel resolution is `scale * frame.size`, but we never persist that. Don't multiply by `backingScaleFactor` anywhere.

### E4. Sudden termination

- Apple notes `applicationWillTerminate(_:)` is **not** called during sudden termination. Stock Flutter macOS apps do not call `ProcessInfo.processInfo.enableSuddenTermination()`, so this is moot for us. But: if some future code path enables sudden termination, `frameAutosaveName` still works (AppKit writes on every user-initiated resize/move, not just at terminate). This is yet another reason to prefer Strategy A.

### E5. Notch on M-series MacBook Pro

- `NSScreen.visibleFrame` excludes the notch / camera-housing area, so 80% × `visibleFrame` is already notch-safe. No special handling needed.
- The bezel-adjacent strips next to the notch are exposed as `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` for menu-bar items only — not relevant for window framing.

### E6. Menu item idempotency ("user triple-clicks Settings while route is already /settings")

- Native side simply calls `channel.invokeMethod("openSettings", nil)` every time — it's cheap and asynchronous.
- Dart side must guard. Pattern: check `GoRouterState.of(context).matchedLocation == '/settings'` before pushing. Or use `appRouter.go('/settings')` (replace) instead of `appRouter.push('/settings')` so duplicates collapse. (Implementation lives in the Dart task subtask, not this research.)

### E7. `awakeFromNib` ordering vs `applicationWillFinishLaunching`

Order of events for a Flutter macOS app launch (verified from XIB load semantics + AppDelegate lifecycle):

1. `main.swift` (auto-generated by `@main` macro on `AppDelegate`) calls `NSApplicationMain`.
2. NSApplicationMain loads `MainMenu.xib`. This instantiates `AppDelegate`, `NSApplication` (File's Owner), and `MainFlutterWindow`. The xib's `<connections>` are wired *here*.
3. `MainFlutterWindow.awakeFromNib()` fires for the window object.
4. `AppDelegate.applicationWillFinishLaunching(_:)` fires.
5. `AppDelegate.applicationDidFinishLaunching(_:)` fires.
6. Window is made visible (key + ordered front).
7. Eventually `applicationWillTerminate(_:)` on quit; or `windowWillClose(_:)` if user closes the last window first.

**Practical implication**: `awakeFromNib` is the *earliest* place where the `FlutterViewController` can be initialized and `engine.binaryMessenger` exists, AND it runs before `applicationDidFinishLaunching` — so by the time the user can click any menu item, the channel is wired. No race.

### E8. XIB literal "Settings…" must use U+2026

The current XIB at `macos/Runner/Base.lproj/MainMenu.xib` line 36 uses `Preferences…` with what appears to be the U+2026 character (`…`), not three periods. Match that convention: use the single Unicode ellipsis. Editors that auto-correct three periods to `…` are fine; raw `...` in the XML will *render* as three periods on screen and visually fail HIG compliance.

### E9. `releasedWhenClosed="NO"` is already set in the XIB

Line 333: `<window … releasedWhenClosed="NO" …>`. This is important — it means `windowWillClose(_:)` fires but the window object stays alive long enough for us to read `self.frame` in the close handler. Don't change this.

### E10. `applicationShouldTerminateAfterLastWindowClosed` already returns true

The current `AppDelegate.swift` returns `true` here, which means closing the main window terminates the app. Combined with E4 and E5, this gives us the desired UX: user closes the window → `windowWillClose` → `applicationWillTerminate` → both save paths run.

### E11. Channel reply discipline

`channel.invokeMethod("openSettings", arguments: nil)` (no `result:` callback variant) is fire-and-forget. If the Dart handler throws, we'd never know — but we also don't care, the side-effect is the navigation. If we ever need confirmation (e.g. to disable the menu while the route is opening), use the `invokeMethod:arguments:result:` variant.

### E12. `setMethodCallHandler:` lifecycle

The channel holds the handler strongly. The bridge object (`MenuChannelBridge`) holds the channel strongly. `MainFlutterWindow` holds the bridge strongly. As long as `MainFlutterWindow` is alive, the channel is alive. When the window is released on app quit, the bridge is released, and the channel deregisters its handler automatically. No manual cleanup required.

### E13. Multiple windows

Out of scope per PRD ("multi-window not supported"). But for the record: `frameAutosaveName` requires unique names per window. If we ever add a second window, give it a distinct autosave name like `fl_picraft.settings`.

### E14. Channel name collisions

`app.fl_picraft/menu` is unique in our app. If a future plugin (e.g. some hypothetical macOS-only Flutter plugin) reuses the same channel name, the second registration silently replaces the first per Flutter's documented behavior. Our reverse-DNS-ish prefix (`app.fl_picraft/`) minimizes collision risk.

### E15. `super.awakeFromNib()` ordering

The current `MainFlutterWindow.awakeFromNib()` (line 13) calls `super.awakeFromNib()` at the *end*. Apple's docs are ambiguous on the right order for `NSWindow`, but in practice calling super last is fine because `NSWindow.awakeFromNib` is a no-op for plain windows. Match the current convention; do not move the `super` call.

---

## Implementation checklist (paste-ready)

For the implementing engineer:

- [ ] Edit `macos/Runner/Base.lproj/MainMenu.xib`:
  - Change `<menuItem title="Preferences…"` → `<menuItem title="Settings…"`.
  - Inside that `<menuItem>`, add `<connections><action selector="openSettings:" target="Voe-Tx-rLC" id="<new-uuid>"/></connections>`.
- [ ] Create `macos/Runner/MenuChannelBridge.swift` with the snippet from Strategy A above.
- [ ] Edit `macos/Runner/MainFlutterWindow.swift`:
  - Add `var menuBridge: MenuChannelBridge?` (or just hold the channel directly if we don't need a wrapper).
  - Set `contentMinSize = NSSize(width: 1280, height: 800)`.
  - Compute and `setFrame(...)` an 80%-centered default before calling `setFrameAutosaveName(...)`.
  - Call `setFrameAutosaveName("fl_picraft.main")` after `setFrame`.
  - Instantiate `MenuChannelBridge` with `flutterViewController.engine.binaryMessenger` and assign to `(NSApp.delegate as? AppDelegate)?.menuBridge`.
- [ ] Edit `macos/Runner/AppDelegate.swift`:
  - Add `var menuBridge: MenuChannelBridge?`.
  - Add `@IBAction func openSettings(_ sender: Any?) { menuBridge?.openSettings() }`.
- [ ] Dart side: create `lib/core/native/menu_channel.dart` with the `setMethodCallHandler` registering `'openSettings'` → router `.go('/settings')`. Call `MenuChannel.bind(...)` after `WidgetsFlutterBinding.ensureInitialized()` in `main.dart`.

---

## Quick reference: relationship between the APIs

```
NSWindow
  ├── frame           : NSRect (points, includes title bar)
  ├── contentMinSize  : NSSize (points, EXCLUDES title bar) ← USE THIS
  ├── minSize         : NSSize (points, INCLUDES title bar)
  ├── setFrame(_:display:)            ← bypasses minSize, USE for restore
  ├── setFrame(_:display:animate:)    ← bypasses minSize too
  ├── setFrameAutosaveName(_:) -> Bool
  ├── saveFrame(usingName:)
  └── setFrameUsingName(_:) -> Bool

NSScreen
  ├── frame           : NSRect (full screen incl. menu bar / dock area)
  ├── visibleFrame    : NSRect ← USE THIS for default sizing
  ├── (class) main    : NSScreen? — the focused screen
  └── (class) screens : [NSScreen] — [0] is primary (menu-bar screen)

NSApplication
  └── didChangeScreenParametersNotification — observe for hotplug

NSApplicationDelegate
  ├── applicationWillFinishLaunching(_:)  ← XIB already loaded
  ├── applicationDidFinishLaunching(_:)   ← windows shown
  └── applicationWillTerminate(_:)        ← save here (Strategy B)

NSWindowDelegate
  └── windowWillClose(_:)                 ← redundant save hook

FlutterMacOS
  FlutterViewController
    └── engine: FlutterEngine
        └── binaryMessenger: FlutterBinaryMessenger
            ↓
            FlutterMethodChannel(name:, binaryMessenger:)
              ├── invokeMethod(_:arguments:)              ← fire-and-forget
              ├── invokeMethod(_:arguments:result:)       ← with reply
              └── setMethodCallHandler(_:)                ← Dart → native

Foundation (NSRect <-> String)
  ├── NSStringFromRect(_:) -> String       "{{x, y}, {w, h}}"
  └── NSRectFromString(_:) -> NSRect       NSZeroRect on parse failure
```

---

## References

### Apple — AppKit primary sources

- [NSWindow.setFrameAutosaveName(_:)](https://developer.apple.com/documentation/appkit/nswindow/setframeautosavename(_:)) — opt into AppKit-managed save/restore. Returns false if another live window owns the name.
- [NSWindow.FrameAutosaveName (typealias)](https://developer.apple.com/documentation/appkit/nswindow/frameautosavename-swift.typealias) — `typealias FrameAutosaveName = String`.
- [NSWindow.saveFrame(usingName:)](https://developer.apple.com/documentation/appkit/nswindow/saveframe(usingname:)) — manual save companion. "The default is owned by the application and stored under the name `NSWindow Frame <name>`."
- [NSWindow.setFrameUsingName(_:)](https://developer.apple.com/documentation/appkit/nswindow/setframeusingname(_:)) — manual restore companion. "Constrained according to the window's minimum and maximum size settings."
- [NSWindow.minSize](https://developer.apple.com/documentation/appkit/nswindow/minsize) — frame including title bar.
- [NSWindow.contentMinSize](https://developer.apple.com/documentation/appkit/nswindow/contentminsize) — **takes precedence over minSize**.
- [NSWindow.setFrame(_:display:)](https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:)) — note: NOT constrained by minSize.
- [NSWindow.setFrame(_:display:animate:)](https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:animate:)) — also bypasses minSize.
- [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe) — area safe to draw, excludes dock / menu bar / notch.
- [NSScreen.main](https://developer.apple.com/documentation/appkit/nsscreen/main) — screen with the key window (NOT primary).
- [NSScreen.screens](https://developer.apple.com/documentation/appkit/nsscreen/screens) — index 0 is primary (menu bar) screen.
- [NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification) — hotplug / resolution change notification.
- [NSApplicationDelegate.applicationWillFinishLaunching(_:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationwillfinishlaunching(_:)).
- [NSApplicationDelegate.applicationWillTerminate(_:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationwillterminate(_:)) — "this method isn't called during sudden termination."
- [NSWindowDelegate.windowWillClose(_:)](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillclose(_:)).

### Apple — Foundation rect serialization

- [NSStringFromRect(_:)](https://developer.apple.com/documentation/foundation/nsstringfromrect(_:)) — `"{{x, y}, {w, h}}"`.
- [NSRectFromString(_:)](https://developer.apple.com/documentation/foundation/nsrectfromstring(_:)) — returns `NSZeroRect` on parse failure.

### Apple — Nibs / XIB

- [Resource Programming Guide → Cocoa Nibs](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingResources/CocoaNibs/CocoaNibs.html) — explains action connections, First Responder (`id=-1`), File's Owner (`id=-2`), action method conventions.

### Apple — HIG

- [Human Interface Guidelines → The menu bar → App menu](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#App-menu) — canonical "Settings…" naming with horizontal ellipsis, ⌘, key equivalent.
- [Human Interface Guidelines → Settings](https://developer.apple.com/design/human-interface-guidelines/settings) — settings UX guidance.

### Apple — SwiftUI (for context only; we don't use SwiftUI here)

- [SwiftUI.Settings](https://developer.apple.com/documentation/swiftui/settings) — SwiftUI's app-level Settings scene; macOS 11+.
- [SwiftUI.OpenSettingsAction](https://developer.apple.com/documentation/swiftui/opensettingsaction) — `@Environment(\.openSettings)`; macOS 14+.
- [SwiftUI.Scene.commands(content:)](https://developer.apple.com/documentation/swiftui/scene/commands(content:)) — SwiftUI menu customization.

### Flutter — macOS embedder

- [FlutterMethodChannel (macOS embedder)](https://api.flutter.dev/macos-embedder/interface_flutter_method_channel.html) — `+methodChannelWithName:binaryMessenger:` and `-invokeMethod:arguments:`.
- [FlutterViewController (macOS embedder)](https://api.flutter.dev/macos-embedder/interface_flutter_view_controller.html) — has `engine: FlutterEngine *` property.
- [FlutterEngine (macOS embedder)](https://api.flutter.dev/macos-embedder/interface_flutter_engine.html) — `binaryMessenger` property.
- [FlutterPluginRegistrar (macOS embedder)](https://api.flutter.dev/macos-embedder/protocol_flutter_plugin_registrar-p.html) — also exposes `messenger` (alternative way to get a binary messenger if we were writing a plugin; we are not).

### Flutter — Platform channels guide

- [Flutter: Writing custom platform-specific code (platform channels)](https://docs.flutter.dev/platform-integration/platform-channels) — channel name convention, type marshaling table for Swift (`bool → NSNumber(value: Bool)`, etc.).

### Related Specs

- `.trellis/spec/frontend/dependencies-and-platforms.md` — referenced from the task PRD; reinforces "no new Flutter plugin dependency" decision for this work.
- `CLAUDE.md` (project root) — target architecture; this task is in the "extremely thin native + Dart bridge" carve-out and is not subject to the standard `data/domain/presentation` split.

---

## Caveats / Not found

- **Could not verify** that Xcode 14+ Flutter `create` templates emit "Settings…" instead of "Preferences…". Empirically, the XIB in this repo (created at project init) still ships `Preferences…`, so for our purposes we must do the rename ourselves regardless of the template's current state.
- **Could not directly fetch** the canonical `MainFlutterWindow.swift` from the Flutter master branch via raw GitHub (404s). However, the embedder API surface confirmed via Apple/Flutter doc pages is sufficient to write the code; pattern is identical to `flutter create -t macos`-generated boilerplate already in this repo.
- **Did not investigate** the `FlutterMenuPlugin` class visible in the macOS embedder class list (`api.flutter.dev/macos-embedder/interface_flutter_menu_plugin.html`). It looks like an internal helper for the `PlatformMenuBar` widget; we are explicitly *not* using `PlatformMenuBar`, so this is out of scope. The XIB-driven menu approach above is independent of `FlutterMenuPlugin`.
- **Did not exhaustively test** `frameAutosaveName` behavior on macOS Tahoe / Sequoia with the notch bezel — relying on Apple's docs that `visibleFrame` already excludes it and that constraint applies on restore too.
