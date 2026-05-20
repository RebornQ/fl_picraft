import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/native/menu_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MenuChannel.bind(onOpenSettings: () => appRouter.go('/settings'));
  runApp(const ProviderScope(child: AppRoot()));
}
