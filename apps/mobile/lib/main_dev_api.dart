import 'package:flutter/widgets.dart';
import 'package:sg_api/sg_api.dart';
import 'package:syncgate/bootstrap.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';
import 'package:syncgate/src/wiring/api_support.dart';

/// The dev flavour against the real Spring Boot API (`services/api`), with the
/// scripted camera standing in for the on-device face pipeline. Start the API
/// first (`services/api/README.md`), then:
///
/// `flutter run --flavor dev -t lib/main_dev_api.dart
///    --dart-define-from-file=env/dev.json`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.resolve(Flavour.dev);
  final clock = ApiClock();
  final api = ApiBackend(
    baseUrl: config.apiBaseUrl,
    deviceKey: config.deviceKey,
    saveFile: saveExportToTemp,
    now: clock.now,
  );
  try {
    clock.offset = await api.serverClockOffset();
  } on ApiError {
    // The server is not reachable yet: the app opens and says so, and keeps
    // the phone's own clock until it is restarted.
  }
  await bootstrap(config, overrides: devApiOverrides(api, clock));
}
