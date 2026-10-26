import 'package:syncgate/bootstrap.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';

/// `--dart-define=DEV_START=gate` skips the setup wizard.
const _devStart = String.fromEnvironment('DEV_START');

Future<void> main() => bootstrap(
  AppConfig.resolve(Flavour.dev),
  // The default depends on a compile-time define, so it is not redundant.
  // ignore: avoid_redundant_argument_values
  overrides: devOverrides(freshInstall: _devStart != 'gate'),
);
