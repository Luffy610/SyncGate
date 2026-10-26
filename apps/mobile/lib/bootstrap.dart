import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/app/syncgate_app.dart';

/// Shared startup for every flavour. Each `main_<flavour>.dart` passes its
/// config and the provider overrides for that flavour (fakes in dev).
Future<void> bootstrap(
  AppConfig config, {
  List<Override> overrides = const [],
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO(E22): route to the encrypted on-device log and opt-in Sentry.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config), ...overrides],
      child: const SyncGateApp(),
    ),
  );
}
