import 'package:syncgate/bootstrap.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';

/// `--dart-define=DEV_START=gate` skips the setup wizard.
const _devStart = String.fromEnvironment('DEV_START');

/// `--dart-define=VISION=real` uses the camera and the real face models.
const _vision = String.fromEnvironment('VISION');

/// `--dart-define=CAMERA_ROTATION=90` (or 0, 180, 270) overrides the camera
/// frame rotation for phones that report it wrongly.
const _rotation = int.fromEnvironment('CAMERA_ROTATION', defaultValue: -1);

/// `--dart-define=VISION_DIAGNOSTICS=true` overlays live face-pipeline
/// numbers on the camera preview and prints them to the console.
const _diagnostics = bool.fromEnvironment('VISION_DIAGNOSTICS');

Future<void> main() => bootstrap(
  AppConfig.resolve(Flavour.dev),
  overrides: devOverrides(
    // Both depend on compile-time defines, so they are not redundant.
    // ignore: avoid_redundant_argument_values
    freshInstall: _devStart != 'gate',
    // Same: set by --dart-define=VISION.
    // ignore: avoid_redundant_argument_values
    realVision: _vision == 'real',
    // Set by --dart-define=CAMERA_ROTATION; null without it.
    // ignore: avoid_redundant_argument_values
    cameraRotation: _rotation < 0 ? null : _rotation,
    // Set by --dart-define=VISION_DIAGNOSTICS.
    // ignore: avoid_redundant_argument_values
    visionDiagnostics: _diagnostics,
  ),
);
