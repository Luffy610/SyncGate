import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/dev/seed.dart';

import 'support/test_app.dart';

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<TestApp> openUnlock(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) async {
  final app = await pumpApp(tester, platform: platform, textScale: textScale);
  await tester.tap(find.bySemanticsLabel('Admin unlock'));
  await tester.pumpAndSettle();
  expect(app.location, Routes.unlock);
  return app;
}

void main() {
  testWidgets('shows the PIN pad, roles and the gate operator note', (
    tester,
  ) async {
    await openUnlock(tester);

    expect(find.text('Admin access'), findsOneWidget);
    expect(find.text('Enter your 6-digit PIN'), findsOneWidget);
    for (final role in ['Owner', 'Admin', 'Gate operator']) {
      expect(find.text(role), findsOneWidget);
    }
    expect(
      find.text(
        "Gate operators can fix gate issues but can't see reports or export "
        'data.',
      ),
      findsOneWidget,
    );
    expect(find.text('Use fingerprint'), findsOneWidget);
  });

  group('signing in', () {
    testWidgets('owner PIN opens Today and is audited', (tester) async {
      final app = await openUnlock(tester);
      await typePin(tester, DemoSeed.ownerPin);

      expect(app.location, Routes.today);
      final mode = app.mode as AdminMode;
      expect(mode.role, Role.owner);
      expect(app.env.backend.audit.entries.map((e) => e.action), [
        'mode.admin',
      ]);
      expect(find.text('Reports'), findsWidgets);
    });

    testWidgets('admin PIN works for the Admin role', (tester) async {
      final app = await openUnlock(tester);
      await tester.tap(find.text('Admin'));
      await tester.pump();
      await typePin(tester, DemoSeed.adminPin);

      expect((app.mode as AdminMode).role, Role.admin);
    });

    testWidgets('gate operator lands on the limited Today without tabs', (
      tester,
    ) async {
      final app = await openUnlock(tester);
      await tester.tap(find.text('Gate operator'));
      await tester.pump();
      await typePin(tester, DemoSeed.operatorPin);

      expect((app.mode as AdminMode).role, Role.gateOperator);
      expect(app.location, Routes.today);
      expect(find.text('Reports'), findsNothing);
    });

    testWidgets('the close button goes back to the gate', (tester) async {
      final app = await openUnlock(tester);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.gate);
      expect(app.mode, isA<GateMode>());
    });

    testWidgets('iOS shows "Back to gate" and Face ID', (tester) async {
      final app = await openUnlock(tester, platform: TargetPlatform.iOS);
      expect(find.text('Use Face ID'), findsOneWidget);
      await tester.tap(find.text('Back to gate'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.gate);
    });
  });

  group('wrong PINs', () {
    testWidgets('a wrong PIN clears the dots and counts the tries left', (
      tester,
    ) async {
      final app = await openUnlock(tester);
      await typePin(tester, '000000');

      expect(find.text('Wrong PIN. 4 tries left.'), findsOneWidget);
      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.unlock);

      await typePin(tester, '000000');
      expect(find.text('Wrong PIN. 3 tries left.'), findsOneWidget);
    });

    testWidgets('a PIN for another role is rejected', (tester) async {
      final app = await openUnlock(tester);
      await typePin(tester, DemoSeed.adminPin);
      expect(find.textContaining('Wrong PIN'), findsOneWidget);
      expect(app.mode, isA<GateMode>());
    });

    testWidgets('five wrong PINs lock the pad with a countdown', (
      tester,
    ) async {
      final app = await openUnlock(tester);
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '000000');
      }

      expect(find.text('Too many tries. Try again in 0:30.'), findsOneWidget);

      // While locked, even the right PIN does nothing.
      await typePin(tester, DemoSeed.ownerPin);
      expect(app.mode, isA<GateMode>());

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Too many tries. Try again in 0:20.'), findsOneWidget);

      app.clock.value = demoMoment.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 21));
      expect(find.textContaining('Too many tries'), findsNothing);

      await typePin(tester, DemoSeed.ownerPin);
      expect(app.mode, isA<AdminMode>());
    });

    testWidgets('the lockout grows after more failures', (tester) async {
      final app = await openUnlock(tester);
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '000000');
      }
      app.clock.value = demoMoment.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      await typePin(tester, '000000');
      expect(find.text('Too many tries. Try again in 1:00.'), findsOneWidget);
    });
  });

  group('biometrics', () {
    testWidgets('fingerprint unlocks the selected role', (tester) async {
      final app = await openUnlock(tester);
      await tester.tap(find.text('Use fingerprint'));
      await tester.pumpAndSettle();
      expect((app.mode as AdminMode).role, Role.owner);
    });

    testWidgets('a failed fingerprint stays on the PIN screen', (tester) async {
      final app = await pumpApp(tester);
      app.env.biometric.succeeds = false;
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use fingerprint'));
      await tester.pumpAndSettle();
      expect(app.mode, isA<GateMode>());
    });

    testWidgets('no biometric option when the phone has none', (tester) async {
      final app = await pumpApp(tester);
      app.env.biometric.kind = BiometricKind.none;
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Use fingerprint'), findsNothing);
    });

    testWidgets('no biometric option when the owner turned it off', (
      tester,
    ) async {
      await pumpApp(
        tester,
        settings: const AppSettings(
          mode: AppModeKind.gate,
          setupStep: 7,
          biometricEnabled: false,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Use fingerprint'), findsNothing);
    });
  });

  group('forgot PIN', () {
    testWidgets('the recovery code sets a new owner PIN', (tester) async {
      final app = await pumpApp(tester);
      final code = await app.env.backend.users.createOwner('123456');
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), code);
      await tester.enterText(find.byType(TextField).at(1), '654321');
      await tester.pump();
      await tester.tap(find.text('Reset PIN'));
      await tester.pumpAndSettle();

      expect(find.text('PIN reset. Sign in with the new PIN.'), findsOneWidget);
      await typePin(tester, '654321');
      expect(app.mode, isA<AdminMode>());
    });

    testWidgets('a wrong recovery code is refused', (tester) async {
      final app = await pumpApp(tester);
      await app.env.backend.users.createOwner('123456');
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'WRONG-CODE');
      await tester.enterText(find.byType(TextField).at(1), '654321');
      await tester.pump();
      await tester.tap(find.text('Reset PIN'));
      await tester.pumpAndSettle();

      expect(find.text("That recovery code isn't right."), findsOneWidget);
    });

    testWidgets('only the owner role offers it', (tester) async {
      await openUnlock(tester);
      expect(find.text('Forgot PIN?'), findsOneWidget);
      await tester.tap(find.text('Admin'));
      await tester.pump();
      expect(find.text('Forgot PIN?'), findsNothing);
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('fits on ${platform.name} at ${scale}x', (tester) async {
        await openUnlock(tester, platform: platform, textScale: scale);
        await typePin(tester, '000000');
        expect(find.textContaining('Wrong PIN'), findsOneWidget);
      });
    }
  }
}
