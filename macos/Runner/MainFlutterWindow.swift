import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Minimum content area: 1280x800 (excludes the ~28pt title bar).
    // `contentMinSize` takes precedence over `minSize` per Apple docs and
    // matches the user-facing expectation of a 1280x800 usable canvas.
    self.contentMinSize = NSSize(width: 1280, height: 800)

    // First-launch default frame: 80% of the primary monitor's
    // `visibleFrame`, centered. `visibleFrame` already excludes the dock,
    // menu bar, and the M-series notch area, so this is notch-safe.
    // `setFrame(_:display:)` is the one setter Apple documents as NOT
    // constrained by minSize; the `max(..., 1280/800)` guards still keep
    // us at or above the min on tiny screens.
    if let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first {
      let visible = screen.visibleFrame
      let w = max(floor(visible.width * 0.80), 1280)
      let h = max(floor(visible.height * 0.80), 800)
      let x = visible.minX + (visible.width - w) / 2
      let y = visible.minY + (visible.height - h) / 2
      self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    // Persist + restore via AppKit's autosave. MUST come AFTER `setFrame`:
    // if UserDefaults already has a saved value under the key
    // `NSWindow Frame fl_picraft.main`, AppKit immediately overrides the
    // default frame we just set; otherwise our 80% default is kept.
    // AppKit also auto-saves on every user resize/move and auto-clamps via
    // `constrainFrameRect:to:` when the saved rect lands off-screen.
    _ = self.setFrameAutosaveName("fl_picraft.main")

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Wire the native -> Dart menu bridge. The engine's binaryMessenger
    // is already available here (FlutterViewController has been
    // instantiated above), so the channel is registered before any
    // menu item can be clicked.
    let bridge = MenuChannelBridge(
      messenger: flutterViewController.engine.binaryMessenger
    )
    (NSApp.delegate as? AppDelegate)?.menuBridge = bridge

    super.awakeFromNib()
  }
}
