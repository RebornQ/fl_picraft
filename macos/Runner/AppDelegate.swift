import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Set by `MainFlutterWindow.awakeFromNib` once the Flutter engine is
  /// up. Held strongly so the underlying `FlutterMethodChannel` stays
  /// alive for the lifetime of the app.
  var menuBridge: MenuChannelBridge?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Wired from `MainMenu.xib`: App menu -> "Settings..." (Cmd+,).
  ///
  /// Parameter is `Any?` so it matches the XIB connection target type
  /// (`NSMenuItem`) without forcing a downcast.
  @IBAction func openSettings(_ sender: Any?) {
    menuBridge?.openSettings()
  }
}
