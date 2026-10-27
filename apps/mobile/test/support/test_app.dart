import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/router.dart';
import 'package:syncgate/src/app/syncgate_app.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';
import 'package:syncgate/src/dev/fakes/fake_services.dart';

import 'fonts.dart';

/// 05:52 on Saturday 24-10-2026: the moment shown in the gate designs.
final demoMoment = DateTime(2026, 10, 24, 5, 52);

/// The running app plus the fakes behind it, so tests can drive and inspect
/// both.
class TestApp {
  new(this.env, this.clock, this.tester);

  final DevEnvironment env;
  final FixedClock clock;
  final WidgetTester tester;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(SyncGateApp)));

  AppMode get mode => container.read(appModeProvider);

  AppModeController get modeController =>
      container.read(appModeProvider.notifier);

  /// Signs in as [role] without going through the PIN screen.
  Future<void> signIn(Role role) async {
    final user = (await env.backend.users.users()).firstWhere(
      (u) => u.role == role,
    );
    await modeController.enterAdmin(user);
    await tester.pumpAndSettle();
  }

  /// Moves the app clock to [time] and lets the UI pick it up.
  Future<void> setTime(DateTime time) async {
    clock.value = time;
    container.invalidate(tickProvider);
    await tester.pumpAndSettle();
  }

  /// The current router location, e.g. `/admin/today`.
  String get location {
    final router = container.read(routerProvider);
    return router.routerDelegate.currentConfiguration.last.matchedLocation;
  }
}

/// Pumps the dev app. [freshInstall] starts the setup wizard; otherwise the
/// app opens on the gate with owner PIN 123456.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  bool freshInstall = false,
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
  DateTime? now,
  AppSettings? settings,
  void Function(DevEnvironment env)? configure,
}) async {
  await loadTestFonts();
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });

  final clock = FixedClock(now ?? demoMoment);
  final env = DevEnvironment(freshInstall: freshInstall, clock: clock);
  if (settings != null) await env.backend.settingsRepo.save(settings);
  configure?.call(env);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...env.overrides(),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            flavour: Flavour.dev,
            licenceBaseUrl: '',
            sentryDsn: '',
          ),
        ),
        tickPeriodProvider.overrideWithValue(Duration.zero),
        lookProvider.overrideWith(() => _FixedLook(platform)),
      ],
      child: const SyncGateApp(),
    ),
  );
  await tester.pumpAndSettle();
  return TestApp(env, clock, tester);
}

class _FixedLook extends LookController {
  new(this.platform);

  final TargetPlatform platform;

  @override
  TargetPlatform? build() => platform;
}

/// Scrolls the page's main scroll view until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(SingleChildScrollView).first,
    const Offset(0, -150),
  );
  await tester.pumpAndSettle();
}
