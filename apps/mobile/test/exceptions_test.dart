import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/router.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/dev/seed.dart';

import 'support/test_app.dart';

Future<TestApp> openExceptions(
  WidgetTester tester, {
  Role role = Role.owner,
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) async {
  final app = await pumpApp(tester, platform: platform, textScale: textScale);
  await app.signIn(role);
  unawaited(app.container.read(routerProvider).push(Routes.exceptions));
  await tester.pumpAndSettle();
  expect(app.location, Routes.exceptions);
  return app;
}

void main() {
  group('list', () {
    testWidgets('shows the four open items in the design order', (
      tester,
    ) async {
      await openExceptions(tester);

      expect(find.text('Exceptions'), findsOneWidget);
      expect(find.text('All 4'), findsOneWidget);
      expect(find.text('Manual 2'), findsOneWidget);
      expect(find.text('Missing OUT 1'), findsOneWidget);
      expect(find.text('Clock 1'), findsOneWidget);

      expect(find.text('MISSING OUT'), findsOneWidget);
      expect(find.text('MANUAL'), findsNWidgets(2));
      expect(find.text('CLOCK'), findsOneWidget);
      expect(find.text('Mohd. Irfan · W-0109'), findsOneWidget);
      expect(find.text('IN 05:51 by face · no OUT mark'), findsOneWidget);
      expect(find.text('Guard G-02 · reason: camera issue'), findsOneWidget);
      expect(find.text('Device clock moved back 14 min'), findsOneWidget);
      expect(
        find.text('3 events flagged · check before payroll'),
        findsOneWidget,
      );
      // Yesterday shows the date, today the time.
      expect(find.text('23-10'), findsNWidgets(3));
      expect(find.text('02:10'), findsOneWidget);
    });

    testWidgets('the chips filter the list', (tester) async {
      await openExceptions(tester);

      await tester.tap(find.text('Manual 2'));
      await tester.pumpAndSettle();
      expect(find.text('Kavita Patil · W-0106'), findsOneWidget);
      expect(find.text('Suresh Rao · W-0119'), findsOneWidget);
      expect(find.text('Mohd. Irfan · W-0109'), findsNothing);

      await tester.tap(find.text('Clock 1'));
      await tester.pumpAndSettle();
      expect(find.text('Device clock moved back 14 min'), findsOneWidget);
      expect(find.text('Kavita Patil · W-0106'), findsNothing);
    });

    testWidgets('a guard entry from the gate shows up here', (tester) async {
      final app = await pumpApp(tester);
      await app.env.backend.exceptions.add(
        ExceptionRecord(
          id: 'new',
          kind: ExceptionKind.manual,
          at: demoMoment,
          workerId: DemoSeed.workerId(112),
          actor: 'G-02',
          reason: ManualReason.maskHelmet,
        ),
      );
      await app.signIn(Role.owner);
      unawaited(app.container.read(routerProvider).push(Routes.exceptions));
      await tester.pumpAndSettle();

      expect(find.text('Manual 3'), findsOneWidget);
      expect(find.text('Ramesh Kumar · W-0112'), findsOneWidget);
      // Suresh Rao's entry has the same reason.
      expect(find.text('Guard G-02 · reason: mask / helmet'), findsNWidgets(2));
      expect(find.text('05:52'), findsOneWidget);
    });

    testWidgets('back goes to Today', (tester) async {
      final app = await openExceptions(tester);
      await tester.tap(find.bySemanticsLabel('Today'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.today);
    });

    testWidgets('an empty list says all clear', (tester) async {
      final app = await pumpApp(tester);
      for (final e in await app.env.backend.exceptions.all()) {
        await app.env.backend.exceptions.resolve(e.id);
      }
      await app.signIn(Role.owner);
      unawaited(app.container.read(routerProvider).push(Routes.exceptions));
      await tester.pumpAndSettle();
      expect(find.text('All clear'), findsOneWidget);
    });
  });

  group('correct record', () {
    Future<TestApp> openSheet(
      WidgetTester tester, {
      Role role = Role.owner,
    }) async {
      final app = await openExceptions(tester, role: role);
      await tester.tap(find.text('Mohd. Irfan · W-0109'));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('shows the record, the IN time and a default OUT', (
      tester,
    ) async {
      await openSheet(tester);

      expect(find.text('Correct record'), findsOneWidget);
      expect(find.text('Mohd. Irfan · W-0109'), findsWidgets);
      expect(find.text('Fri, 23-10-2026 · Day shift · Dyeing'), findsOneWidget);
      expect(find.text('IN · FACE'), findsOneWidget);
      expect(find.text('05:51'), findsOneWidget);
      expect(find.text('OUT · NEW'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
    });

    testWidgets('the audit line previews exactly what will be recorded', (
      tester,
    ) async {
      await openSheet(tester);

      final preview = tester.widget<Text>(
        find.byKey(const ValueKey('audit-preview')),
      );
      expect(
        preview.data,
        'Audit log will record: OUT none → 14:00, by Owner, '
        '24-10-2026, 5:52 AM. Shows in the exceptions report.',
      );
    });

    testWidgets('saving needs a reason', (tester) async {
      final app = await openSheet(tester);

      await tester.tap(find.text('Save correction'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Correct record'), findsOneWidget);
      expect(await app.env.backend.attendance.lastEvent('w-0109'), isNotNull);
      expect(
        (await app.env.backend.exceptions.all()).where((e) => !e.resolved),
        hasLength(4),
      );
    });

    testWidgets('saves a correction event, resolves the item and audits it', (
      tester,
    ) async {
      final app = await openSheet(tester);

      await tester.tap(find.text('Choose a reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot to mark OUT — supervisor confirmed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();

      expect(find.text('Record corrected'), findsOneWidget);
      expect(find.text('All 3'), findsOneWidget);
      expect(find.text('Mohd. Irfan · W-0109'), findsNothing);

      final events = await app.env.backend.attendance.eventsBetween(
        DateTime(2026, 10, 23),
        DateTime(2026, 10, 24),
      );
      final fix = events.firstWhere((e) => e.method == MarkMethod.correction);
      expect(fix.workerId, DemoSeed.workerId(109));
      expect(fix.direction, Direction.checkOut);
      expect(fix.at, DateTime(2026, 10, 23, 14));
      expect(fix.markedBy, 'Owner');
      expect(fix.reason, 'Forgot to mark OUT — supervisor confirmed');

      final audit = app.env.backend.audit.entries.firstWhere(
        (e) => e.action == 'attendance.corrected',
      );
      expect(audit.actor, 'Owner');
      expect(audit.detail, contains('W-0109 OUT none → 14:00'));
    });

    testWidgets('the OUT time can be changed with the stepper', (tester) async {
      final app = await openSheet(tester);

      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('minute up'));
      await tester.tap(find.bySemanticsLabel('minute up'));
      await tester.tap(find.bySemanticsLabel('minute up'));
      await tester.tap(find.bySemanticsLabel('minute up'));
      await tester.tap(find.bySemanticsLabel('minute up'));
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('14:05'), findsOneWidget);

      await tester.tap(find.text('Choose a reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong direction was recorded'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();

      final events = await app.env.backend.attendance.eventsBetween(
        DateTime(2026, 10, 23),
        DateTime(2026, 10, 24),
      );
      expect(
        events.firstWhere((e) => e.method == MarkMethod.correction).at,
        DateTime(2026, 10, 23, 14, 5),
      );
    });

    testWidgets('an OUT time before the IN time is refused', (tester) async {
      final app = await openSheet(tester);

      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.bySemanticsLabel('hour down'));
        await tester.pump();
      }
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('04:00'), findsOneWidget);

      await tester.tap(find.text('Choose a reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong direction was recorded'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save correction'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Correct record'), findsOneWidget);
      expect(
        (await app.env.backend.attendance.eventsBetween(
          DateTime(2026, 10, 23),
          DateTime(2026, 10, 24),
        )).where((e) => e.method == MarkMethod.correction),
        isEmpty,
      );
    });

    testWidgets('"Other…" asks for a typed reason', (tester) async {
      final app = await openSheet(tester);

      await tester.tap(find.text('Choose a reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Power cut');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();

      final events = await app.env.backend.attendance.eventsBetween(
        DateTime(2026, 10, 23),
        DateTime(2026, 10, 24),
      );
      expect(
        events.firstWhere((e) => e.method == MarkMethod.correction).reason,
        'Power cut',
      );
    });

    testWidgets('an admin may correct too', (tester) async {
      await openSheet(tester, role: Role.admin);
      expect(find.text('Correct record'), findsOneWidget);
    });

    testWidgets('the corrected day no longer counts as missing OUT on Today', (
      tester,
    ) async {
      final app = await openSheet(tester);
      await tester.tap(find.text('Choose a reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot to mark OUT — supervisor confirmed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Today'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.today);
      expect(find.text('3 records need review'), findsOneWidget);
      expect(find.text('2 manual · 1 clock change'), findsOneWidget);
    });
  });

  group('review', () {
    testWidgets('a manual entry is reviewed and leaves the list', (
      tester,
    ) async {
      final app = await openExceptions(tester);

      await tester.tap(find.text('Kavita Patil · W-0106'));
      await tester.pumpAndSettle();
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Guard G-02 · reason: camera issue'), findsWidgets);

      await tester.tap(find.text('Mark reviewed'));
      await tester.pumpAndSettle();

      expect(find.text('Marked as reviewed'), findsOneWidget);
      expect(find.text('Kavita Patil · W-0106'), findsNothing);
      expect(find.text('Manual 1'), findsOneWidget);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('exception.reviewed'),
      );
    });

    testWidgets('a clock change is reviewed the same way', (tester) async {
      await openExceptions(tester);
      await tester.tap(find.text('Device clock moved back 14 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark reviewed'));
      await tester.pumpAndSettle();
      expect(find.text('Device clock moved back 14 min'), findsNothing);
      expect(find.text('All 3'), findsOneWidget);
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('fits on ${platform.name} at ${scale}x', (tester) async {
        await openExceptions(tester, platform: platform, textScale: scale);
        await tester.tap(find.text('Mohd. Irfan · W-0109'));
        await tester.pumpAndSettle();
        expect(find.text('Correct record'), findsOneWidget);
      });
    }
  }
}
