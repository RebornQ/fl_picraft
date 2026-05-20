import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

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
