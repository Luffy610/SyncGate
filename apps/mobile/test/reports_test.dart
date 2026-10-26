import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/routes.dart';

import 'support/test_app.dart';

Future<TestApp> openReports(
  WidgetTester tester, {
  Role role = Role.owner,
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) async {
  final app = await pumpApp(tester, platform: platform, textScale: textScale);
  await app.signIn(role);
  await tester.tap(find.text('Reports').last);
  await tester.pumpAndSettle();
  expect(app.location, Routes.reports);
  return app;
}

Future<void> resolveAllExceptions(TestApp app) async {
  for (final e in await app.env.backend.exceptions.all()) {
    await app.env.backend.exceptions.resolve(e.id);
  }
}

void main() {
  group('monthly muster', () {
    testWidgets('shows the filters, the summary and the table', (tester) async {
      await openReports(tester);

      expect(find.text('Daily'), findsOneWidget);
      expect(find.text('Monthly muster'), findsOneWidget);
      expect(find.text('Oct 2026'), findsOneWidget);
      expect(find.text('Dept: All'), findsOneWidget);
      expect(find.text('Shift: All'), findsOneWidget);
      expect(find.text('24 workers · 21 working days'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      expect(find.text('WORKER'), findsOneWidget);
      expect(find.text('LATE'), findsOneWidget);
      expect(find.text('OT H'), findsOneWidget);
      // First rows by name.
      expect(find.text('Anil Chauhan'), findsOneWidget);
      expect(find.text('Anita Sharma'), findsOneWidget);
    });

    testWidgets('the numbers match the attendance records', (tester) async {
      final app = await openReports(tester);
      final rows = await app.env.backend.reports.monthly(
        ReportFilter(month: DateTime(2026, 10)),
      );

      for (final r in rows) {
        // Every working day up to yesterday is present or absent; today
        // only counts once the worker has marked.
        expect(r.present + r.absent, inInclusiveRange(19, 21));
        expect(r.late, lessThanOrEqualTo(r.present));
        expect(r.days.length, 31);
        expect(r.days.where((d) => d == 'WO'), hasLength(3)); // 4, 11, 18
      }
      expect(rows.length, 24);
    });

    testWidgets('workers with open exceptions are flagged', (tester) async {
      final app = await openReports(tester);
      final rows = await app.env.backend.reports.monthly(
        ReportFilter(month: DateTime(2026, 10)),
      );
      final flagged = rows
          .where((r) => r.hasOpenExceptions)
          .map((r) => r.worker.name);
      expect(
        flagged,
        containsAll(['Mohd. Irfan', 'Kavita Patil', 'Suresh Rao']),
      );
    });

    testWidgets('a department filter narrows the table', (tester) async {
      await openReports(tester);

      await tester.tap(find.text('Dept: All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cutting'));
      await tester.pumpAndSettle();

      expect(find.text('Dept: Cutting'), findsOneWidget);
      expect(find.text('4 workers · 21 working days'), findsOneWidget);
      expect(find.text('Deepak Yadav'), findsOneWidget);
      expect(find.text('Anita Sharma'), findsNothing);
    });

    testWidgets('a shift filter narrows the table', (tester) async {
      await openReports(tester);

      await tester.tap(find.text('Shift: All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();

      expect(find.text('1 worker · 21 working days'), findsOneWidget);
      expect(find.text('Prakash Kale'), findsOneWidget);
    });

    testWidgets('a month with no data says so', (tester) async {
      await openReports(tester);

      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 2026'));
      await tester.pumpAndSettle();

      expect(find.text('No records for this month'), findsOneWidget);
      expect(find.text('Sep 2026'), findsOneWidget);
    });

    testWidgets('"See all" opens the full muster grid', (tester) async {
      final app = await openReports(tester);

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.reportsMuster);
      expect(find.text('Monthly muster'), findsOneWidget);
      expect(find.text('Oct 2026'), findsOneWidget);
      expect(
        find.text('P present · A absent · L late · WO weekly off'),
        findsOneWidget,
      );
      expect(find.text('Anil Chauhan'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('WO'), findsWidgets);
      expect(find.text('P'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Reports'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.reports);
    });
  });

  group('daily', () {
    testWidgets('lists today with IN and OUT times', (tester) async {
      await openReports(tester);

      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();

      expect(find.text('Attendance on Sat, 24-10-2026'), findsOneWidget);
      expect(find.text('Anita Sharma'), findsOneWidget);
      expect(find.text('IN 05:51 · OUT --:--'), findsWidgets);
      expect(find.text('Present'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
    });

    testWidgets('steps back a day and shows the missing OUT', (tester) async {
      await openReports(tester);
      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Attendance on Fri, 23-10-2026'), findsOneWidget);
      expect(find.text('Mohd. Irfan'), findsOneWidget);
    });
  });

  group('export', () {
    Future<void> tapExport(WidgetTester tester) async {
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pump();
      await tester.tap(find.text('Export & share'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists Excel and Tally with the mapping status', (
      tester,
    ) async {
      await openReports(tester);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pump();

      expect(find.text('EXPORT FOR PAYROLL'), findsOneWidget);
      expect(find.text('Excel (.xlsx)'), findsOneWidget);
      expect(find.text('Template: Payroll — default columns'), findsOneWidget);
      expect(find.text('Tally Prime (XML)'), findsOneWidget);
      expect(
        find.text('23 of 24 matched to Tally employees · 1 to map'),
        findsOneWidget,
      );
    });

    testWidgets('open exceptions ask for confirmation first', (tester) async {
      final app = await openReports(tester);
      await tapExport(tester);

      expect(find.text('4 records still need review'), findsOneWidget);
      expect(
        find.text('They will be marked with a flag in the export.'),
        findsOneWidget,
      );
      expect(app.env.backend.export.exports, isEmpty);
    });

    testWidgets('"Review first" opens Exceptions without exporting', (
      tester,
    ) async {
      final app = await openReports(tester);
      await tapExport(tester);

      await tester.tap(find.text('Review first'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.exceptions);
      expect(app.env.backend.export.exports, isEmpty);
    });

    testWidgets('"Export anyway" builds the file and opens the share sheet', (
      tester,
    ) async {
      final app = await openReports(tester);
      await tapExport(tester);

      await tester.tap(find.text('Export anyway'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Preparing the file…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(app.env.share.shared, ['syncgate-muster-2026-10.xlsx']);
      expect(
        find.text('File ready: syncgate-muster-2026-10.xlsx'),
        findsOneWidget,
      );
      expect(app.env.backend.export.exports.single.$1, ExportFormat.excel);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('report.exported'),
      );
    });

    testWidgets('without open exceptions it exports straight away', (
      tester,
    ) async {
      final app = await openReports(tester);
      await resolveAllExceptions(app);
      await tester.pumpAndSettle();
      await tapExport(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.textContaining('still need review'), findsNothing);
      expect(app.env.share.shared, hasLength(1));
    });

    testWidgets('Tally exports XML for the filtered workers', (tester) async {
      final app = await openReports(tester);
      await resolveAllExceptions(app);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dept: All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Packing'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -500),
      );
      await tester.pump();
      await tester.tap(find.text('Tally Prime (XML)'));
      await tester.pump();
      await tester.tap(find.text('Export & share'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(app.env.share.shared, ['syncgate-muster-2026-10.xml']);
      final (format, filter) = app.env.backend.export.exports.single;
      expect(format, ExportFormat.tally);
      expect(filter.department, 'Packing');
    });

    testWidgets('export is never blocked by the licence state', (tester) async {
      final app = await openReports(tester);
      await resolveAllExceptions(app);
      await app.env.backend.licence.startTrial();
      await tester.pumpAndSettle();
      await tapExport(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(app.env.share.shared, hasLength(1));
    });
  });

  group('menu and roles', () {
    testWidgets('the menu opens the Tally mapping', (tester) async {
      final app = await openReports(tester);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tally mapping'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.settingsTally);
    });

    testWidgets('an admin can use Reports', (tester) async {
      await openReports(tester, role: Role.admin);
      expect(find.text('24 workers · 21 working days'), findsOneWidget);
    });

    testWidgets('a gate operator never sees the tab', (tester) async {
      final app = await pumpApp(tester);
      await app.signIn(Role.gateOperator);
      expect(find.text('Reports'), findsNothing);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('fits on ${platform.name} at ${scale}x', (tester) async {
          await openReports(tester, platform: platform, textScale: scale);
          expect(find.text('Oct 2026'), findsOneWidget);
        });
      }
    }
  });
}
