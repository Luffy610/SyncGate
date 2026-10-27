import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';

import 'support/test_app.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  // Let any toast leave: it floats over the bottom buttons.
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// The whole of Phase 1's frontend on the demo back end: a fresh install,
/// the setup wizard, the first enrolment, a mark at the gate, an admin
/// correction and a payroll export (frontend plan §8, integration row).
void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('fresh install to payroll export on ${platform.name}', (
      tester,
    ) async {
      final app = await pumpApp(tester, freshInstall: true, platform: platform);
      final env = app.env;

      // ---- Setup wizard -------------------------------------------------
      expect(app.location, Routes.setupLanguage);
      await tapText(tester, 'Continue · आगे बढ़ें');

      await tester.tap(find.text('Scan QR on invoice'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Activate');
      expect(app.location, Routes.setupShift);
      expect((await env.backend.licence.current()).state, LicenceState.active);

      await tapText(tester, 'Continue'); // first shift, defaults
      expect(app.location, Routes.setupCamera);

      await tapText(tester, 'Check again');
      expect(find.text('Light good · 240 lux'), findsOneWidget);
      await tapText(tester, 'Continue');
      expect(app.location, Routes.setupKiosk);

      if (platform == TargetPlatform.android) {
        await tapText(tester, 'Pin SyncGate now');
      } else {
        env.kiosk.set(KioskState.locked);
        await tester.pumpAndSettle();
      }
      await tapText(tester, 'Continue');
      expect(app.location, Routes.setupOwner);

      await tapDigits(tester, '482915');
      await tapDigits(tester, '482915');
      expect(find.text('KX7M-4PQ2-9TWD'), findsOneWidget);
      await tapText(tester, "I've written it down");
      await tapText(tester, 'Continue');
      expect(app.location, Routes.setupFirstWorker);

      // ---- First enrolment, straight from the wizard ---------------------
      await tapText(tester, 'Enrol first worker');
      expect(app.mode, isA<AdminMode>());
      expect(app.location, Routes.enrolDetails);

      final fields = find.byType(TextField);
      if (platform == TargetPlatform.android) {
        await tester.enterText(fields.at(0), 'Geeta Rani');
        await tester.enterText(fields.at(2), '12031998');
        await tester.tap(find.text('Department'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stitching').last);
        await tester.pumpAndSettle();
        await tester.enterText(fields.at(3), 'Machine operator');
      } else {
        await tester.enterText(fields.at(0), 'Geeta Rani');
        await tester.enterText(fields.at(2), '12031998');
        await tester.tap(find.text('Department'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stitching').last);
        await tester.pumpAndSettle();
        await tester.enterText(fields.at(3), 'Machine operator');
      }
      await tester.pump();
      await tapText(tester, 'Next');
      expect(app.location, Routes.enrolNotice);

      await tester.tap(
        find.text('Worker has heard or read this notice and agrees'),
      );
      await tester.pump();
      await tapText(tester, 'Agree & capture face');
      expect(app.location, Routes.enrolFace);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(app.location, Routes.workers);
      expect(find.text('Geeta Rani enrolled'), findsOneWidget);
      expect(find.text('Geeta Rani'), findsWidgets);

      // ---- Back to the gate: the new worker walks up ---------------------
      await tester.tap(find.text('Back to gate'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.gate);

      final geeta = (await env.backend.workers.all()).firstWhere(
        (w) => w.name == 'Geeta Rani',
      );
      env.gateVision.match(geeta.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('IN · 05:52 AM'), findsOneWidget);
      expect(find.text('Geeta Rani'), findsWidgets);
      expect(find.textContaining('of 23 marked IN'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // ---- Unlock with the PIN made in setup -----------------------------
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();
      await tapDigits(tester, '482915');
      expect(app.mode, isA<AdminMode>());
      expect(app.location, Routes.today);
      expect(find.text('4 records need review'), findsOneWidget);

      // ---- Correct the missing OUT --------------------------------------
      await tapText(tester, '4 records need review');
      expect(app.location, Routes.exceptions);
      await tapText(tester, 'Mohd. Irfan · W-0109');
      await tapText(tester, 'Choose a reason');
      await tapText(tester, 'Forgot to mark OUT — supervisor confirmed');
      await tapText(tester, 'Save correction');
      expect(find.text('Record corrected'), findsOneWidget);
      expect(find.text('All 3'), findsOneWidget);

      // ---- Export for payroll -------------------------------------------
      // Back from Exceptions (a text on iOS, an arrow on Android).
      await tester.tap(
        platform == TargetPlatform.iOS
            ? find.text('Today').last
            : find.bySemanticsLabel('Today'),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Reports');
      expect(app.location, Routes.reports);
      expect(find.text('25 workers · 21 working days'), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pump();
      await tester.tap(find.text('Export & share'));
      await tester.pumpAndSettle();
      expect(find.text('3 records still need review'), findsOneWidget);
      await tester.tap(find.text('Export anyway'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(env.share.shared, ['syncgate-muster-2026-10.xlsx']);

      // ---- Done: back to the gate ---------------------------------------
      await tapText(tester, 'Today');
      await tapText(tester, 'Start gate mode');
      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.gate);

      // The audit trail tells the same story, in order.
      expect(env.backend.audit.entries.map((e) => e.action).toList(), [
        'setup.completed',
        'mode.admin',
        'worker.created',
        'consent.recorded',
        'worker.enrolled',
        'mode.gate',
        'mode.admin',
        'attendance.corrected',
        'report.exported',
        'mode.gate',
      ]);
    });
  }
}
