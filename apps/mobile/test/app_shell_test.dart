import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/router.dart';
import 'package:syncgate/src/app/routes.dart';

import 'support/test_app.dart';

void main() {
  group('redirect rules', () {
    test('setup only reaches steps up to the current one', () {
      expect(redirectFor(const SetupMode(2), Routes.setupLanguage), isNull);
      expect(redirectFor(const SetupMode(2), Routes.setupLicence), isNull);
      expect(
        redirectFor(const SetupMode(2), Routes.setupCamera),
        Routes.setupLicence,
      );
      expect(
        redirectFor(const SetupMode(1), Routes.gate),
        Routes.setupLanguage,
      );
    });

    test('gate allows gate, manual entry and unlock only', () {
      const mode = GateMode();
      expect(redirectFor(mode, Routes.gate), isNull);
      expect(redirectFor(mode, Routes.manual), isNull);
      expect(redirectFor(mode, Routes.unlock), isNull);
      expect(redirectFor(mode, Routes.today), Routes.gate);
      expect(redirectFor(mode, Routes.setupLanguage), Routes.gate);
    });

    AdminMode admin(Role role) => AdminMode(
      AdminSession(
        user: AppUser(id: 'u', name: 'U', role: role),
        startedAt: demoMoment,
      ),
    );

    test('owner reaches every admin page, nothing outside', () {
      final mode = admin(Role.owner);
      expect(redirectFor(mode, Routes.reports), isNull);
      expect(redirectFor(mode, Routes.settingsBackup), isNull);
      expect(redirectFor(mode, Routes.gate), Routes.today);
    });

    test('admin cannot open backup or users', () {
      final mode = admin(Role.admin);
      expect(redirectFor(mode, Routes.reports), isNull);
      expect(redirectFor(mode, Routes.settingsBackup), Routes.settings);
      expect(redirectFor(mode, Routes.settingsUsers), Routes.settings);
    });

    test('gate operator only gets Today and manual entry', () {
      final mode = admin(Role.gateOperator);
      expect(redirectFor(mode, Routes.today), isNull);
      expect(redirectFor(mode, Routes.manual), isNull);
      expect(redirectFor(mode, Routes.reports), Routes.today);
      expect(redirectFor(mode, Routes.workers), Routes.today);
      expect(redirectFor(mode, Routes.settings), Routes.today);
    });
  });

  group('mode transitions', () {
    testWidgets('a fresh install opens the setup wizard', (tester) async {
      final app = await pumpApp(tester, freshInstall: true);
      expect(app.mode, const SetupMode(1));
      expect(app.location, Routes.setupLanguage);
    });

    testWidgets('an installed app opens on the gate', (tester) async {
      final app = await pumpApp(tester);
      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.gate);
    });

    testWidgets('admin shows the paused banner and the four tabs', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      expect(app.location, Routes.today);
      expect(
        find.text("Gate is paused — workers can't mark attendance"),
        findsOneWidget,
      );
      for (final tab in ['Today', 'Workers', 'Reports', 'Settings']) {
        expect(find.text(tab), findsWidgets);
      }
    });

    testWidgets('tabs switch between branches', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      await tester.tap(find.text('Reports').last);
      await tester.pumpAndSettle();
      expect(app.location, Routes.reports);

      await tester.tap(find.text('Workers').last);
      await tester.pumpAndSettle();
      expect(app.location, Routes.workers);
    });

    testWidgets('"Back to gate" returns to the gate and is audited', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      await tester.tap(find.text('Back to gate'));
      await tester.pumpAndSettle();

      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.gate);
      final actions = app.env.backend.audit.entries.map((e) => e.action);
      expect(actions, containsAllInOrder(['mode.admin', 'mode.gate']));
    });

    testWidgets('a gate operator has no tabs and cannot reach Reports', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.gateOperator);
      expect(app.location, Routes.today);
      expect(find.text('Reports'), findsNothing);

      app.container.read(routerProvider).go(Routes.reports);
      await tester.pumpAndSettle();
      expect(app.location, Routes.today);
    });

    testWidgets('the mode is saved so a restart can resume', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.admin);
      final saved = await app.env.backend.settingsRepo.load();
      expect(saved.mode, AppModeKind.admin);
    });
  });

  group('auto-return to gate', () {
    testWidgets('after two idle minutes in admin', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      await tester.pump(const Duration(minutes: 1, seconds: 59));
      expect(app.mode, isA<AdminMode>());

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.gate);
    });

    testWidgets('a touch restarts the timer', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      await tester.pump(const Duration(minutes: 1, seconds: 30));
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(minutes: 1, seconds: 30));
      expect(app.mode, isA<AdminMode>());
    });

    testWidgets('face capture holds the timer', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);
      app.container.read(idleHoldProvider.notifier).hold();

      await tester.pump(const Duration(minutes: 5));
      expect(app.mode, isA<AdminMode>());

      app.container.read(idleHoldProvider.notifier).release();
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await tester.pumpAndSettle();
      expect(app.mode, isA<GateMode>());
    });

    testWidgets('the timeout is a setting', (tester) async {
      final app = await pumpApp(
        tester,
        settings: const AppSettings(
          mode: AppModeKind.gate,
          setupStep: 7,
          idleMinutes: 5,
        ),
      );
      await app.signIn(Role.owner);
      await tester.pump(const Duration(minutes: 4, seconds: 50));
      expect(app.mode, isA<AdminMode>());
    });

    testWidgets('returning from the background leaves admin', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pumpAndSettle();

      expect(app.mode, isA<GateMode>());
    });
  });
}
