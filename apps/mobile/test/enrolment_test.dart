import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/router.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';
import 'package:syncgate/src/dev/seed.dart';

import 'support/test_app.dart';

Future<TestApp> openDetails(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  Role role = Role.owner,
  void Function(DevEnvironment env)? configure,
}) async {
  final app = await pumpApp(tester, platform: platform, configure: configure);
  await app.signIn(role);
  await tester.tap(
    platform == TargetPlatform.iOS
        ? find.bySemanticsLabel('Enrol worker')
        : find.text('Enrol worker'),
  );
  await tester.pumpAndSettle();
  expect(app.location, Routes.enrolDetails);
  return app;
}

/// Fills the Android form (fields in design order).
Future<void> fillDetails(
  WidgetTester tester, {
  String name = 'Geeta Rani',
  String dob = '12031998',
  String designation = 'Machine operator',
  String department = 'Stitching',
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(2), dob);
  await tester.tap(find.text('Department'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(department).last);
  await tester.pumpAndSettle();
  await tester.enterText(fields.at(3), designation);
  await tester.pump();
}

Future<void> nextStep(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

Future<void> toNotice(WidgetTester tester) async {
  await fillDetails(tester);
  await nextStep(tester);
}

Future<void> agreeAndCapture(WidgetTester tester) async {
  await tester.tap(
    find.text('Worker has heard or read this notice and agrees'),
  );
  await tester.pump();
  await tester.tap(find.text('Agree & capture face'));
  await tester.pumpAndSettle();
}

/// Lets the fake camera run through every angle.
Future<void> finishCapture(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  group('step 1 · details', () {
    testWidgets('starts with the next free ID and the current shift', (
      tester,
    ) async {
      await openDetails(tester);

      expect(find.text('New worker'), findsOneWidget);
      expect(find.text('W-0126'), findsOneWidget);
      expect(find.text('Auto-assigned. You can change it.'), findsOneWidget);
      expect(find.text('Day · 06:00–14:00'), findsOneWidget);
      expect(find.text('हिन्दी · Hindi'), findsOneWidget);
      expect(
        find.text(
          'Notices and voice prompts for this worker use this language.',
        ),
        findsOneWidget,
      );
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Notice'), findsOneWidget);
      expect(find.text('Face'), findsOneWidget);
    });

    testWidgets('the step labels are not clipped on a phone', (tester) async {
      await openDetails(tester);

      for (final label in ['Details', 'Notice', 'Face']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
    });

    testWidgets('missing fields block Next and creates nothing', (
      tester,
    ) async {
      final app = await openDetails(tester);

      await nextStep(tester);
      expect(find.text('Required'), findsWidgets);
      expect(app.location, Routes.enrolDetails);
      expect((await app.env.backend.workers.all()).length, 25);
    });

    testWidgets('the date of birth is formatted and the age checked', (
      tester,
    ) async {
      await openDetails(tester);
      final dob = find.byType(TextField).at(2);

      await tester.enterText(dob, '12031998');
      await tester.pump();
      expect(find.text('12-03-1998'), findsOneWidget);
      expect(
        find.text('✓ Age 28 — must be 18 or older to enrol'),
        findsOneWidget,
      );

      await tester.enterText(dob, '01012015');
      await tester.pump();
      expect(
        find.text(
          'Age 11 — must be 18 or older to enrol. '
          "This worker can't be enrolled.",
        ),
        findsOneWidget,
      );

      await tester.enterText(dob, '31021998');
      await tester.pump();
      expect(find.text('Enter the date as DD-MM-YYYY.'), findsOneWidget);
    });

    testWidgets('someone turning 18 today can be enrolled', (tester) async {
      await openDetails(tester);
      await tester.enterText(find.byType(TextField).at(2), '24102008');
      await tester.pump();
      expect(
        find.text('✓ Age 18 — must be 18 or older to enrol'),
        findsOneWidget,
      );
    });

    testWidgets('someone under 18 cannot be enrolled', (tester) async {
      final app = await openDetails(tester);
      await fillDetails(tester, dob: '25102008');
      await nextStep(tester);

      expect(app.location, Routes.enrolDetails);
      expect((await app.env.backend.workers.all()).length, 25);
    });

    testWidgets('a worker ID already in use is refused', (tester) async {
      final app = await openDetails(tester);
      await fillDetails(tester);
      await tester.enterText(find.byType(TextField).at(1), 'W-0101');
      await nextStep(tester);

      expect(find.text('That worker ID is already used.'), findsOneWidget);
      expect(app.location, Routes.enrolDetails);
    });

    testWidgets('a new department can be added from the picker', (
      tester,
    ) async {
      final app = await openDetails(tester);

      await tester.tap(find.text('Department'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add new department'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Spinning');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Spinning'), findsOneWidget);
      expect(await app.env.backend.workers.departments(), contains('Spinning'));
    });

    testWidgets('Cancel leaves without creating anyone', (tester) async {
      final app = await openDetails(tester);
      await fillDetails(tester);
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.today);
      expect((await app.env.backend.workers.all()).length, 25);
    });

    testWidgets('iOS groups the fields under Worker, Work and Contact', (
      tester,
    ) async {
      await openDetails(tester, platform: TargetPlatform.iOS);

      expect(find.text('WORKER'), findsOneWidget);
      expect(find.text('WORK'), findsOneWidget);
      expect(find.text('CONTACT & LANGUAGE'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('a gate operator cannot reach it', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.gateOperator);
      app.container.read(routerProvider).go(Routes.enrolDetails);
      await tester.pumpAndSettle();
      expect(app.location, Routes.today);
    });
  });

  group('step 2 · privacy notice', () {
    testWidgets('creates the worker and shows the notice in their language', (
      tester,
    ) async {
      final app = await openDetails(tester);
      await toNotice(tester);

      expect(app.location, Routes.enrolNotice);
      expect(find.text('Privacy notice'), findsOneWidget);
      expect(find.text('Show to Geeta Rani in their language'), findsOneWidget);
      expect(find.text('आपकी हाज़िरी की जानकारी'), findsOneWidget);
      expect(find.text('सुनाएँ'), findsOneWidget);
      expect(
        find.textContaining('[CONSENT OR LEGITIMATE USE — TBD]'),
        findsOneWidget,
      );

      final workers = await app.env.backend.workers.all();
      final created = workers.firstWhere((w) => w.name == 'Geeta Rani');
      expect(created.code, 'W-0126');
      expect(created.faceStatus, FaceStatus.needsFace);
      expect(created.department, 'Stitching');
    });

    testWidgets('the continue button waits for the consent box', (
      tester,
    ) async {
      final app = await openDetails(tester);
      await toNotice(tester);

      await tester.tap(find.text('Agree & capture face'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(app.location, Routes.enrolNotice);
      expect(app.env.backend.consent.records, isEmpty);

      await agreeAndCapture(tester);
      expect(app.location, Routes.enrolFace);
    });

    testWidgets('consent is recorded with the notice language and admin', (
      tester,
    ) async {
      final app = await openDetails(tester);
      await toNotice(tester);
      await agreeAndCapture(tester);

      final record = app.env.backend.consent.records.single;
      expect(record.version, 'v0-draft');
      expect(record.language, AppLanguage.hi);
      expect(record.adminId, 'u-owner');
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('consent.recorded'),
      );
    });

    testWidgets('read aloud speaks the notice in the worker language', (
      tester,
    ) async {
      final app = await openDetails(tester);
      await toNotice(tester);
      await tester.tap(find.text('सुनाएँ'));
      await tester.pump();
      expect(app.env.voice.calls, contains('notice:hi'));
    });

    testWidgets('going back keeps the details and does not duplicate the '
        'worker', (tester) async {
      final app = await openDetails(tester);
      await toNotice(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.enrolDetails);
      expect(find.text('Geeta Rani'), findsOneWidget);

      await nextStep(tester);
      final workers = await app.env.backend.workers.all();
      expect(workers.where((w) => w.name == 'Geeta Rani'), hasLength(1));
    });
  });

  group('step 3 · face capture', () {
    Future<TestApp> toCapture(
      WidgetTester tester, {
      void Function(DevEnvironment env)? configure,
    }) async {
      final app = await openDetails(tester, configure: configure);
      await toNotice(tester);
      await agreeAndCapture(tester);
      return app;
    }

    testWidgets('shows the progress tiles and the privacy note', (
      tester,
    ) async {
      await toCapture(tester);

      expect(find.text('Geeta Rani'), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Look straight at the camera'), findsOneWidget);
      expect(find.text('सीधे कैमरे की ओर देखें'), findsOneWidget);
      for (final tile in ['Front', 'Left', 'Right', 'Mask']) {
        expect(find.text(tile), findsOneWidget);
      }
      expect(find.text('Optional'), findsOneWidget);
      expect(
        find.text(
          'Photos are deleted once the face code is made. '
          'The code stays on this phone only.',
        ),
        findsOneWidget,
      );
      expect(find.text('Skip mask sample'), findsOneWidget);
    });

    testWidgets('moves through the angles and enrols the worker', (
      tester,
    ) async {
      final app = await toCapture(tester);

      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Slowly turn your head left'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await finishCapture(tester);

      expect(app.location, Routes.workers);
      expect(find.text('Geeta Rani enrolled'), findsOneWidget);
      final worker = (await app.env.backend.workers.all()).firstWhere(
        (w) => w.name == 'Geeta Rani',
      );
      expect(worker.faceStatus, FaceStatus.enrolled);
      expect(app.env.enrolment.finished, [worker.id]);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        containsAll(['worker.created', 'consent.recorded', 'worker.enrolled']),
      );
    });

    testWidgets('the mask sample can be skipped', (tester) async {
      final app = await toCapture(tester);

      await tester.tap(find.text('Skip mask sample'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(app.location, Routes.workers);
      final worker = (await app.env.backend.workers.all()).firstWhere(
        (w) => w.name == 'Geeta Rani',
      );
      expect(worker.faceStatus, FaceStatus.enrolled);
    });

    testWidgets('capture holds the idle timer', (tester) async {
      final app = await toCapture(
        tester,
        configure: (env) =>
            env.enrolment.stepEvery = const Duration(minutes: 3),
      );

      await tester.pump(const Duration(minutes: 5));
      expect(app.mode, isA<AdminMode>());
      expect(app.location, Routes.enrolFace);
    });

    testWidgets('a duplicate face warns and Cancel leaves the worker without '
        'a face', (tester) async {
      final app = await toCapture(
        tester,
        configure: (env) => env.enrolment.duplicateOf = DemoSeed.workerId(112),
      );
      await finishCapture(tester);

      expect(
        find.text('This face looks like Ramesh Kumar (W-0112)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(app.location, Routes.workers);
      final worker = (await app.env.backend.workers.all()).firstWhere(
        (w) => w.name == 'Geeta Rani',
      );
      expect(worker.faceStatus, FaceStatus.needsFace);
    });

    testWidgets('a duplicate can be overridden with a reason, which is '
        'audited', (tester) async {
      final app = await toCapture(
        tester,
        configure: (env) => env.enrolment.duplicateOf = DemoSeed.workerId(112),
      );
      await finishCapture(tester);

      await tester.tap(find.text('Override with reason'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Twin brothers');
      await tester.tap(find.text('Continue').last);
      await tester.pumpAndSettle();

      expect(app.location, Routes.workers);
      final worker = (await app.env.backend.workers.all()).firstWhere(
        (w) => w.name == 'Geeta Rani',
      );
      expect(worker.faceStatus, FaceStatus.enrolled);
      final entry = app.env.backend.audit.entries.firstWhere(
        (e) => e.action == 'worker.enrolled.duplicateOverride',
      );
      expect(entry.detail, contains('Twin brothers'));
    });

    testWidgets('closing asks first and keeps the worker as "Needs face"', (
      tester,
    ) async {
      final app = await toCapture(tester);

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Stop enrolling Geeta Rani?'), findsOneWidget);

      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.enrolFace);

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.workers);
      expect(app.env.enrolment.cancelled, isNotEmpty);
      expect(find.text('Needs face 2'), findsOneWidget);
    });

    testWidgets('quality hints show over the preview', (tester) async {
      final app = await toCapture(tester);
      app.env.enrolment.emitQuality(QualityIssue.tooDark);
      await tester.pump();
      await tester.pump();
      expect(find.text('Too dark — move closer to the light'), findsOneWidget);

      app.env.enrolment.emitQuality(null);
      await tester.pump();
      await tester.pump();
      expect(find.text('Too dark — move closer to the light'), findsNothing);
    });
  });

  group('look', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('the whole flow fits on ${platform.name} at ${scale}x', (
          tester,
        ) async {
          final app = await pumpApp(
            tester,
            platform: platform,
            textScale: scale,
          );
          await app.signIn(Role.owner);
          app.container.read(routerProvider).go(Routes.enrolDetails);
          await tester.pumpAndSettle();
          expect(find.text('New worker'), findsOneWidget);
        });
      }
    }
  });
}
