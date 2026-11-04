import 'package:syncgate/bootstrap.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';

/// `--dart-define=DEV_START=gate` skips the setup wizard.
const _devStart = String.fromEnvironment('DEV_START');

/// `--dart-define=VISION=real` uses the camera and the real face models.
const _vision = String.fromEnvironment('VISION');

Future<void> main() => bootstrap(
  AppConfig.resolve(Flavour.dev),
  overrides: devOverrides(
    // Both depend on compile-time defines, so they are not redundant.
    // ignore: avoid_redundant_argument_values
    freshInstall: _devStart != 'gate',
    // Same: set by --dart-define=VISION.
    // ignore: avoid_redundant_argument_values
    realVision: _vision == 'real',
  ),
);
