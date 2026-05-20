import Cocoa
import FlutterMacOS

/// Thin Swift wrapper around the menu MethodChannel.
///
/// Owned by `MainFlutterWindow`; referenced by `AppDelegate` so menu
/// IBActions can fire `invokeMethod` without re-instantiating the channel.
///
/// Direction: native -> Dart only for now. The handler is set so that any
/// incoming Dart -> native call replies `FlutterMethodNotImplemented`
/// (reserved for future use).
final class MenuChannelBridge {
  static let channelName = "app.fl_picraft/menu"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    // No native-side handlers yet; reply unimplemented to keep the
    // channel symmetric.
    self.channel.setMethodCallHandler { _, result in
      result(FlutterMethodNotImplemented)
    }
  }

  /// Native -> Dart: tell Flutter to navigate to `/settings`.
  ///
  /// Fire-and-forget; idempotency (already-on-/settings) is handled on
  /// the Dart side via `appRouter.go('/settings')`.
  func openSettings() {
    channel.invokeMethod("openSettings", arguments: nil)
  }
}
