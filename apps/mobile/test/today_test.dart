import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';

import 'support/test_app.dart';

void main() {
  group('Today · owner', () {
    testWidgets('shows the running shift and its numbers', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      expect(find.text('Today'), findsWidgets);
      expect(find.text('Sat, 24-10-2026 · 5:52 AM'), findsOneWidget);
      expect(find.text('Day shift is running'), findsOneWidget);
      expect(find.text('06:00–14:00 · 22 workers expected'), findsOneWidget);
      expect(find.text('Offline OK'), findsOneWidget);
      expect(find.text('Start gate mode'), findsOneWidget);

      // 16 of 22 have marked IN; nobody is late or absent yet.
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('16'), findsNWidgets(2)); // present + on premises
      expect(find.text('of 22 expected'), findsOneWidget);
      expect(find.text('after 06:10'), findsOneWidget);
      expect(find.text('0 went OUT'), findsOneWidget);
    });

    testWidgets('counts late and absent once the shift is underway', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);
      await app.setTime(DateTime(2026, 10, 24, 10, 42));

      expect(find.text('Sat, 24-10-2026 · 10:42 AM'), findsOneWidget);
      // Six workers never came: absent. One is on leave.
      expect(find.text('6'), findsOneWidget);
      expect(find.text('1 on leave'), findsOneWidget);
    });

    testWidgets('the shift chips switch the numbers', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();
      expect(find.text('of 1 expected'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('of 23 expected'), findsOneWidget);
    });

    testWidgets('lists what needs review and opens Exceptions', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      expect(find.text('4 records need review'), findsOneWidget);
      expect(
        find.text('2 manual · 1 missing OUT · 1 clock change'),
        findsOneWidget,
      );

      await tester.tap(find.text('4 records need review'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.exceptions);
    });

    testWidgets('warns about an old backup and backs up from the card', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      expect(find.text('Last backup 8 days ago'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      await tester.pump();
      await tester.tap(find.text('Back up'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Backing up…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Backup saved'), findsOneWidget);
      expect(find.text('Last backup 8 days ago'), findsNothing);
      final info = await app.env.backend.backup.current();
      expect(info.lastBackupAt, demoMoment);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('backup.manual'),
      );
    });

    testWidgets('a recent backup shows no warning', (tester) async {
      final app = await pumpApp(tester);
      await tester.runAsync(app.env.backend.backup.backupNow);
      await app.signIn(Role.owner);
      expect(find.textContaining('Last backup'), findsNothing);
    });

    testWidgets('"Start gate mode" returns to the gate', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);

      await tester.tap(find.text('Start gate mode'));
      await tester.pumpAndSettle();
      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.gate);
    });

    testWidgets('shows a trial banner', (tester) async {
      final app = await pumpApp(tester);
      await app.env.backend.licence.startTrial();
      await app.signIn(Role.owner);
      expect(find.text('Free trial · 30 days left'), findsOneWidget);
    });
  });

  group('Today · look and roles', () {
    testWidgets('Android has the Enrol worker button', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Enrol worker'), findsOneWidget);
    });

    testWidgets('iOS has a plus in the top bar instead', (tester) async {
      final app = await pumpApp(tester, platform: TargetPlatform.iOS);
      await app.signIn(Role.owner);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.bySemanticsLabel('Enrol worker'), findsOneWidget);
    });

    testWidgets('the Enrol button opens the enrolment form', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);
      await tester.tap(find.text('Enrol worker'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.enrolDetails);
    });

    testWidgets('an admin does not see the backup card', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.admin);
      expect(find.text('4 records need review'), findsOneWidget);
      expect(find.text('Last backup 8 days ago'), findsNothing);
    });

    testWidgets('a gate operator sees the numbers and Manual entry only', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.gateOperator);

      expect(find.text('Present'), findsOneWidget);
      expect(find.text('4 records need review'), findsNothing);
      expect(find.text('Last backup 8 days ago'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(SgNavBar), findsNothing);

      await tester.tap(find.text('Manual entry'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.manual);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('fits on ${platform.name} at ${scale}x', (tester) async {
          final app = await pumpApp(
            tester,
            platform: platform,
            textScale: scale,
          );
          await app.signIn(Role.owner);
          expect(find.text('Present'), findsOneWidget);
        });
      }
    }
  });
}
