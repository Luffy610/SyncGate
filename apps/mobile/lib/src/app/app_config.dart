import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build flavours (ADR-0021).
enum Flavour { dev, staging, prod }

/// Compile-time configuration, read from `env/<flavour>.json` via
/// `--dart-define-from-file`.
final class AppConfig {
  const new({
    required this.flavour,
    required this.licenceBaseUrl,
    required this.sentryDsn,
  });

  /// Builds the config for [expected], checking that the env file passed to
  /// the build matches the entry point. A missing env file is allowed (tests,
  /// quick runs); a mismatched one is a build mistake and fails fast.
  factory resolve(
    Flavour expected, {
    String declaredFlavour = const String.fromEnvironment('BUILD_FLAVOUR'),
    String licenceBaseUrl = const String.fromEnvironment('LICENCE_BASE_URL'),
    String sentryDsn = const String.fromEnvironment('SENTRY_DSN'),
  }) {
    if (declaredFlavour.isNotEmpty && declaredFlavour != expected.name) {
      final fix = '--dart-define-from-file=env/${expected.name}.json';
      throw StateError(
        'Entry point is for "${expected.name}" but the build used '
        'env/$declaredFlavour.json. Pass $fix.',
      );
    }
    return AppConfig(
      flavour: expected,
      licenceBaseUrl: licenceBaseUrl,
      sentryDsn: sentryDsn,
    );
  }

  final Flavour flavour;
  final String licenceBaseUrl;
  final String sentryDsn;

  bool get isProd => flavour == Flavour.prod;
}

/// Overridden in `bootstrap` with the config for the running flavour.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
