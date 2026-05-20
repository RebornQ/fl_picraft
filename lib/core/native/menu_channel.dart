import 'package:flutter/services.dart';

/// Native -> Dart bridge for the macOS App-menu Settings... item.
///
/// Wired in [main] before [runApp]; the macOS native side
/// (`MenuChannelBridge.swift`) calls `openSettings` when the user
/// picks the menu item or hits Cmd+,.
///
/// Only listens to the `openSettings` method today; any other method
/// throws [MissingPluginException] so unexpected native -> Dart calls
/// surface loudly during development instead of being silently
/// swallowed.
class MenuChannel {
  MenuChannel._();

  /// Channel name shared with `macos/Runner/MenuChannelBridge.swift`.
  /// Reverse-DNS-ish prefix keeps room for future channels under the
  /// same namespace (e.g. `app.fl_picraft/window`).
  static const String name = 'app.fl_picraft/menu';

  static const MethodChannel _channel = MethodChannel(name);

  /// Bind the channel. Idempotent — calling twice replaces the handler.
  ///
  /// [onOpenSettings] is invoked synchronously inside the channel
  /// handler when the native side sends `openSettings`. Implementations
  /// should be cheap (e.g. `appRouter.go('/settings')`) — long work
  /// should be scheduled via `Future.microtask` instead of blocking
  /// the handler.
  static void bind({required void Function() onOpenSettings}) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openSettings':
          onOpenSettings();
          return null;
        default:
          throw MissingPluginException(
            'MenuChannel: unknown method ${call.method}',
          );
      }
    });
  }
}
