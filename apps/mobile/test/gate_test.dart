import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/application/attendance_use_cases.dart';
import 'package:syncgate/src/dev/seed.dart';

import 'support/test_app.dart';

final String rameshId = DemoSeed.workerId(112);

/// Lets state changes and the 150 ms cross-fade finish.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('scanning shows the prompt, shift, progress and last mark', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Look at the screen'), findsOneWidget);
    expect(find.text('no need to touch'), findsOneWidget);
    expect(find.text('Liveness check on'), findsOneWidget);
    expect(find.text('Day shift · 06:00–14:00'), findsOneWidget);
    expect(find.textContaining('of 22 marked IN'), findsOneWidget);
    expect(find.text('6 not yet'), findsOneWidget);
    expect(find.text('05:52'), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('Offline · saved on this phone'), findsOneWidget);
  });

  testWidgets('the screen stays awake and dims when nobody is there', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    expect(app.env.screen.keepAwake, isTrue);
    expect(app.env.gateVision.running, isTrue);

    await tester.pump(const Duration(seconds: 61));
    expect(app.env.screen.dimmed, isTrue);

    app.env.gateVision.emit(const FaceSeen(faceSizeRatio: 0.4));
    await settle(tester);
    expect(app.env.screen.dimmed, isFalse);
  });

  group('a recognised worker', () {
    testWidgets('turns the panel green, stores the mark, then returns', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.env.gateVision.match(rameshId);
      await settle(tester);

      expect(find.text('IN · 05:52 AM'), findsOneWidget);
      expect(find.text('Ramesh Kumar'), findsWidgets);
      expect(find.text('स्वागत है, Ramesh'), findsOneWidget);
      expect(find.text('W-0112 · Weaving · on time'), findsOneWidget);
      expect(find.text('Voice: “Ramesh, इन”'), findsOneWidget);
      expect(find.textContaining('17 of 22'), findsOneWidget);

      // The mark is stored before the confirmation is on screen.
      final stored = await app.env.backend.attendance.lastEvent(rameshId);
      expect(stored?.direction, Direction.checkIn);
      expect(stored?.method, MarkMethod.face);

      expect(app.env.voice.calls, [
        'earcon:success',
        'phrase:markedIn:hi',
        'name:Ramesh:hi',
      ]);

      await tester.pump(const Duration(milliseconds: 1500));
      await settle(tester);
      expect(find.text('Look at the screen'), findsOneWidget);
      expect(find.text('IN · 05:52 AM'), findsNothing);
    });

    testWidgets('a late arrival is labelled late', (tester) async {
      final app = await pumpApp(tester, now: DateTime(2026, 10, 24, 6, 25));
      app.env.gateVision.match(rameshId);
      await settle(tester);
      expect(find.text('W-0112 · Weaving · late'), findsOneWidget);
    });

    testWidgets('a repeat inside two minutes stores nothing', (tester) async {
      final app = await pumpApp(tester);
      app.env.gateVision.match(rameshId);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester);

      app.clock.value = demoMoment.add(const Duration(seconds: 70));
      app.env.gateVision.match(rameshId);
      await settle(tester);

      expect(find.text('Already marked IN at 05:52 AM'), findsOneWidget);
      expect(find.text('Nothing was saved again.'), findsOneWidget);
      final events = await app.env.backend.attendance.eventsBetween(
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
      );
      expect(events.where((e) => e.workerId == rameshId), hasLength(1));
    });

    testWidgets('the next mark after the cooldown is OUT', (tester) async {
      final app = await pumpApp(tester);
      app.env.gateVision.match(rameshId);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester);

      app.clock.value = demoMoment.add(const Duration(minutes: 3));
      app.env.gateVision.match(rameshId);
      await settle(tester);

      expect(find.text('OUT · 05:55 AM'), findsOneWidget);
      expect(find.text('फिर मिलेंगे, Ramesh'), findsOneWidget);
    });

    testWidgets('an unknown ID is treated as not recognised', (tester) async {
      final app = await pumpApp(tester);
      app.env.gateVision.match('w-unknown');
      await settle(tester);
      expect(find.text('Not recognised'), findsOneWidget);
    });
  });

  group('not recognised', () {
    testWidgets('shows a hint and counts down, then retries on its own', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.env.gateVision
        ..emit(const QualityHint(QualityIssue.covered))
        ..noMatch();
      await settle(tester);

      expect(find.text('Not recognised'), findsOneWidget);
      expect(
        find.textContaining('Take off the helmet or mask, then look again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Trying again in 3 s.'), findsOneWidget);
      expect(app.env.voice.calls, contains('earcon:failure'));

      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Trying again in 2 s.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Look at the screen'), findsOneWidget);
    });

    testWidgets('"Try again" goes straight back to scanning', (tester) async {
      final app = await pumpApp(tester);
      app.env.gateVision.noMatch();
      await settle(tester);

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Look at the screen'), findsOneWidget);
    });

    testWidgets('nothing is stored for a face that is not accepted', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.env.gateVision.noMatch();
      await settle(tester);

      final events = await app.env.backend.attendance.eventsBetween(
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
      );
      expect(
        events.length,
        DemoSeed().events.where((e) => e.at.day == 24).length,
      );
    });
  });

  group('guard fallback', () {
    Future<void> openManual(WidgetTester tester, TestApp app) async {
      app.env.gateVision.noMatch();
      await settle(tester);
      await tester.tap(find.text('Guard: pick worker from list'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists only workers who are not marked yet', (tester) async {
      final app = await pumpApp(tester);
      await openManual(tester, app);

      expect(app.location, Routes.manual);
      expect(find.text('Manual entry'), findsOneWidget);
      expect(find.text('NOT MARKED YET · 6'), findsOneWidget);
      for (final name in [
        'Ramesh Kumar',
        'Kavita Patil',
        'Suresh Rao',
        'Meena Kumari',
        'Vijay Thakur',
        'Pooja Verma',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Deepak Yadav'), findsNothing);
    });

    testWidgets('search filters by name and ID', (tester) async {
      final app = await pumpApp(tester);
      await openManual(tester, app);

      await tester.enterText(find.byType(TextField), 'w-0119');
      await tester.pump();
      expect(find.text('Suresh Rao'), findsOneWidget);
      expect(find.text('Ramesh Kumar'), findsNothing);
    });

    testWidgets('save needs a worker and a reason, then flags the entry', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await openManual(tester, app);

      expect(find.text('Save'), findsOneWidget);

      await tester.ensureVisible(find.text('Ramesh Kumar'));
      await tester.tap(find.text('Ramesh Kumar'));
      await tester.pump();
      expect(find.text('Save IN · Ramesh'), findsOneWidget);

      // No reason yet: saving does nothing.
      await tester.tap(find.text('Save IN · Ramesh'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(app.location, Routes.manual);

      await tester.tap(find.text('Mask / helmet'));
      await tester.pump();
      await tester.tap(find.text('Save IN · Ramesh'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.gate);
      expect(find.text('Saved: Ramesh Kumar marked IN'), findsOneWidget);

      final event = await app.env.backend.attendance.lastEvent(rameshId);
      expect(event?.method, MarkMethod.manual);
      expect(event?.reason, 'maskHelmet');
      expect(event?.markedBy, 'G-02');

      final exceptions = await app.env.backend.exceptions.all();
      final created = exceptions.where((e) => e.workerId == rameshId);
      expect(created.single.kind, ExceptionKind.manual);
      expect(created.single.reason, ManualReason.maskHelmet);

      final audit = app.env.backend.audit.entries.map((e) => e.action);
      expect(audit, contains('attendance.manual'));
    });

    testWidgets('Cancel returns to the gate without saving', (tester) async {
      final app = await pumpApp(tester);
      await openManual(tester, app);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.gate);
      final today = await app.env.backend.attendance.eventsBetween(
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
      );
      expect(today.where((e) => e.workerId == rameshId), isEmpty);
    });
  });

  group('manual entry rules', () {
    testWidgets('a worker can have at most three manual entries a day', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      final manual = app.container.read(markManualAttendanceProvider).call;
      for (var i = 0; i < 3; i++) {
        final result = await manual(
          workerId: rameshId,
          reason: ManualReason.injury,
          actor: 'G-02',
        );
        expect(result.isOk, isTrue);
      }
      final fourth = await manual(
        workerId: rameshId,
        reason: ManualReason.injury,
        actor: 'G-02',
      );
      expect(fourth.fold((_) => null, (f) => f), isA<ManualLimitReached>());
    });
  });

  group('chrome', () {
    testWidgets('the language chip switches the gate to Hindi first', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      expect(find.text('स्क्रीन की ओर देखें'), findsOneWidget);
      expect(
        find.text('Look at the screen · no need to touch'),
        findsOneWidget,
      );
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('warns when the phone is not pinned', (tester) async {
      final app = await pumpApp(tester);
      expect(find.textContaining('Not pinned'), findsOneWidget);

      app.env.kiosk.set(KioskState.locked);
      await settle(tester);
      expect(find.textContaining('Not pinned'), findsNothing);
    });

    testWidgets('iOS says Guided Access is off', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.iOS);
      expect(find.text('Guided Access is off'), findsOneWidget);
    });

    testWidgets('the lock button opens admin unlock', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.bySemanticsLabel('Admin unlock'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.unlock);
    });

    testWidgets('a camera failure pauses the gate', (tester) async {
      await pumpApp(
        tester,
        configure: (env) => env.gateVision.failOnStart = true,
      );
      expect(find.text('Gate is paused'), findsOneWidget);
      expect(
        find.text("The camera isn't available. Check the camera permission."),
        findsOneWidget,
      );
    });
  });

  group('every state fits on both looks at 1.0x and 1.3x text', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${platform.name} $scale', (tester) async {
          final app = await pumpApp(
            tester,
            platform: platform,
            textScale: scale,
          );
          expect(find.text('Look at the screen'), findsOneWidget);

          app.env.gateVision.match(rameshId);
          await settle(tester);
          expect(find.text('Ramesh Kumar'), findsWidgets);
          await tester.pump(const Duration(milliseconds: 1600));

          app.clock.value = demoMoment.add(const Duration(seconds: 30));
          app.env.gateVision.match(rameshId);
          await settle(tester);
          expect(find.textContaining('Already marked'), findsOneWidget);
          await tester.pump(const Duration(seconds: 3));

          app.env.gateVision.noMatch();
          await settle(tester);
          expect(find.text('Not recognised'), findsOneWidget);
        });
      }
    }
  });
}
