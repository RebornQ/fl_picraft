// Unit tests for [MenuChannel]: the macOS App-menu -> /settings bridge.
//
// macOS native side (MenuChannelBridge.swift) sends `openSettings` to
// the channel `app.fl_picraft/menu`. Dart side responds by invoking the
// callback registered via `MenuChannel.bind(...)`.
//
// These tests simulate the native -> Dart direction by hand-encoding
// a `MethodCall` and pushing it through the default platform messenger.

import 'dart:async';

import 'package:fl_picraft/core/native/menu_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<ByteData?> sendMethodCall(MethodCall call) {
    final encoded = codec.encodeMethodCall(call);
    final completer = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      MenuChannel.name,
      encoded,
      completer.complete,
    );
    return completer.future;
  }

  group('MenuChannel', () {
    tearDown(() {
      // Detach any handler set by previous tests so they can't bleed
      // through. setMethodCallHandler(null) is the documented reset.
      const MethodChannel(MenuChannel.name).setMethodCallHandler(null);
    });

    test('invokes onOpenSettings when native sends openSettings', () async {
      var fired = 0;
      MenuChannel.bind(onOpenSettings: () => fired++);

      await sendMethodCall(const MethodCall('openSettings'));

      expect(fired, 1);
    });

    test('idempotent rebinding replaces the previous handler', () async {
      var firstFired = 0;
      var secondFired = 0;
      MenuChannel.bind(onOpenSettings: () => firstFired++);
      MenuChannel.bind(onOpenSettings: () => secondFired++);

      await sendMethodCall(const MethodCall('openSettings'));

      expect(firstFired, 0, reason: 'second bind should replace first');
      expect(secondFired, 1);
    });

    test('replies null on unknown method (channel-level contract)', () async {
      // Implementation detail of MethodChannel.setMethodCallHandler:
      // when the registered handler throws MissingPluginException, the
      // framework swallows it and replies null to the native side.
      // That's the user-observable behavior of "unknown method" — both
      // when no handler is registered AND when the handler explicitly
      // throws MissingPluginException. We rely on this for forward
      // compat: future native -> Dart methods we haven't bound yet
      // won't crash, they just no-op.
      MenuChannel.bind(onOpenSettings: () {});

      final reply = await sendMethodCall(const MethodCall('unknown'));

      expect(reply, isNull);
    });

    test('does not invoke onOpenSettings for unknown methods', () async {
      // Belt-and-braces: even though the channel replies null, the
      // callback wired to `openSettings` must NEVER be reached by
      // some other method name. Catch dispatch typos / regressions.
      var fired = 0;
      MenuChannel.bind(onOpenSettings: () => fired++);

      await sendMethodCall(const MethodCall('OpenSettings')); // case-sensitive
      await sendMethodCall(const MethodCall('open_settings'));
      await sendMethodCall(const MethodCall(''));

      expect(fired, 0);
    });
  });
}
