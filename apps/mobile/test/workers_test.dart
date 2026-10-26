import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/dev/seed.dart';

import 'support/test_app.dart';

Future<TestApp> openWorkers(
  WidgetTester tester, {
  Role role = Role.owner,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final app = await pumpApp(tester, platform: platform);
  await app.signIn(role);
  await tester.tap(find.text('Workers').last);
  await tester.pumpAndSettle();
  expect(app.location, Routes.workers);
  return app;
}

void main() {
  group('Workers list', () {
    testWidgets('shows counts, needs-face first, then by name', (tester) async {
      await openWorkers(tester);

      expect(find.text('All 25'), findsOneWidget);
      expect(find.text('Not in 6'), findsOneWidget);
      expect(find.text('Needs face 1'), findsOneWidget);

      final names = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data);
      final order = names.whereType<String>().toList();
      expect(
        order.indexOf('Sunita Devi'),
        lessThan(order.indexOf('Anil Chauhan')),
      );
      expect(
        order.indexOf('Anil Chauhan'),
        lessThan(order.indexOf('Anita Sharma')),
      );
    });

    testWidgets('each row shows the ID, department, shift and status', (
      tester,
    ) async {
      await openWorkers(tester);

      expect(find.text('W-0125 · Stitching · Day'), findsOneWidget);
      expect(find.text('Needs face'), findsWidgets);
      expect(find.text('IN 05:51'), findsWidgets);
      expect(find.text('Not in'), findsWidgets);
    });

    testWidgets('the filters narrow the list', (tester) async {
      await openWorkers(tester);

      await tester.tap(find.text('Needs face 1'));
      await tester.pumpAndSettle();
      expect(find.text('Sunita Devi'), findsOneWidget);
      expect(find.text('Anita Sharma'), findsNothing);

      await tester.tap(find.text('Not in 6'));
      await tester.pumpAndSettle();
      expect(find.text('Kavita Patil'), findsOneWidget);
      expect(find.text('Anita Sharma'), findsNothing);
      expect(find.text('Sunita Devi'), findsNothing);
    });

    testWidgets('search matches names and IDs', (tester) async {
      await openWorkers(tester);

      await tester.enterText(find.byType(TextField), 'irfan');
      await tester.pumpAndSettle();
      expect(find.text('Mohd. Irfan'), findsOneWidget);
      expect(find.text('Anita Sharma'), findsNothing);

      await tester.enterText(find.byType(TextField), 'w-0118');
      await tester.pumpAndSettle();
      expect(find.text('Anita Sharma'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No workers match your search.'), findsOneWidget);
    });

    testWidgets('a mark at the gate shows up here at once', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.owner);
      await tester.tap(find.text('Workers').last);
      await tester.pumpAndSettle();
      expect(find.text('Not in 6'), findsOneWidget);

      await app.env.backend.attendance.append(
        AttendanceEvent(
          id: 'x',
          workerId: DemoSeed.workerId(112),
          at: demoMoment,
          direction: Direction.checkIn,
          method: MarkMethod.face,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not in 5'), findsOneWidget);
    });

    testWidgets('an empty phone invites the first enrolment', (tester) async {
      final app = await pumpApp(tester);
      for (final w in await app.env.backend.workers.all()) {
        await app.env.backend.workers.delete(w.id);
      }
      await app.signIn(Role.owner);
      await tester.tap(find.text('Workers').last);
      await tester.pumpAndSettle();

      expect(find.text('No workers yet'), findsOneWidget);
      await tester.tap(find.text('Enrol worker').last);
      await tester.pumpAndSettle();
      expect(app.location, Routes.enrolDetails);
    });

    testWidgets('a gate operator cannot reach the list', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.gateOperator);
      expect(find.text('Workers'), findsNothing);
      expect(app.location, Routes.today);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('fits on ${platform.name}', (tester) async {
        await openWorkers(tester, platform: platform);
        expect(find.text('All 25'), findsOneWidget);
      });
    }
  });

  group('Worker profile', () {
    Future<TestApp> openProfile(
      WidgetTester tester,
      String name, {
      Role role = Role.owner,
    }) async {
      final app = await openWorkers(tester, role: role);
      await tester.enterText(find.byType(TextField), name);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('shows details, face status and data held', (tester) async {
      final app = await openProfile(tester, 'Anita Sharma');

      expect(app.location, Routes.worker(DemoSeed.workerId(118)));
      expect(find.text('W-0118'), findsOneWidget);
      expect(find.text('IN 05:51'), findsOneWidget);
      expect(find.text('Packing'), findsOneWidget);
      expect(find.text('Face code saved on this phone'), findsOneWidget);
      expect(find.text('Re-enrol face'), findsOneWidget);
      expect(find.text('No notice recorded'), findsOneWidget);
      expect(
        find.textContaining('The face code never leaves this phone'),
        findsOneWidget,
      );
    });

    testWidgets('a worker without a face can be captured', (tester) async {
      final app = await openProfile(tester, 'Sunita Devi');

      expect(find.text('No face code yet'), findsOneWidget);
      await tester.tap(find.text('Capture face'));
      await tester.pumpAndSettle();
      // No notice yet, so the privacy notice comes first.
      expect(app.location, Routes.enrolNotice);
      expect(find.text('आपकी हाज़िरी की जानकारी'), findsOneWidget);
    });

    testWidgets('deactivating asks first, is audited and can be undone', (
      tester,
    ) async {
      final app = await openProfile(tester, 'Anita Sharma');

      await tester.ensureVisible(find.text('Deactivate worker'));
      await tester.tap(find.text('Deactivate worker'));
      await tester.pumpAndSettle();
      expect(find.text('Deactivate Anita Sharma?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      var worker = await app.env.backend.workers.byId(DemoSeed.workerId(118));
      expect(worker?.active, isTrue);

      await tester.tap(find.text('Deactivate worker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate worker').last);
      await tester.pumpAndSettle();
      worker = await app.env.backend.workers.byId(DemoSeed.workerId(118));
      expect(worker?.active, isFalse);
      expect(find.text('Inactive'), findsOneWidget);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('worker.deactivated'),
      );

      await tester.tap(find.text('Reactivate worker'));
      await tester.pumpAndSettle();
      worker = await app.env.backend.workers.byId(DemoSeed.workerId(118));
      expect(worker?.active, isTrue);
    });

    testWidgets('only the owner can delete a worker and their data', (
      tester,
    ) async {
      final app = await openProfile(tester, 'Anita Sharma');

      await tester.ensureVisible(find.text('Delete worker and data'));
      await tester.tap(find.text('Delete worker and data'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Anita Sharma?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(app.location, Routes.workers);
      expect(
        find.descendant(
          of: find.byType(SgCardList),
          matching: find.text('Anita Sharma'),
        ),
        findsNothing,
      );
      expect(
        await app.env.backend.workers.byId(DemoSeed.workerId(118)),
        isNull,
      );
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('worker.deleted'),
      );
    });

    testWidgets('an admin cannot delete', (tester) async {
      await openProfile(tester, 'Anita Sharma', role: Role.admin);
      expect(find.text('Deactivate worker'), findsOneWidget);
      expect(find.text('Delete worker and data'), findsNothing);
    });

    testWidgets('back returns to the list', (tester) async {
      final app = await openProfile(tester, 'Anita Sharma');
      await tester.tap(find.bySemanticsLabel('Workers').first);
      await tester.pumpAndSettle();
      expect(app.location, Routes.workers);
    });
  });
}
