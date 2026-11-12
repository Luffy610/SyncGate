import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/app/routes.dart';

import 'support/test_app.dart';

void main() {
  group('restore from a backup', () {
    Future<TestApp> openRestore(WidgetTester tester) async {
      final app = await pumpApp(tester, freshInstall: true);
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('is offered on the first setup step and opens', (tester) async {
      final app = await openRestore(tester);
      expect(app.location, Routes.setupRestore);
      expect(find.text('Restore from backup'), findsOneWidget);
      expect(find.text('No file chosen'), findsOneWidget);
    });

    testWidgets('needs a file and a passphrase before Restore works', (
      tester,
    ) async {
      await openRestore(tester);

      await tester.tap(find.text('Choose backup file'));
      await tester.pumpAndSettle();
      expect(find.text('demo.sgbackup'), findsOneWidget);

      // File chosen but no passphrase yet: tapping Restore does nothing.
      await tester.tap(find.text('Restore').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Wrong passphrase'), findsNothing);
    });

    testWidgets('a wrong passphrase is explained and nothing changes', (
      tester,
    ) async {
      final app = await openRestore(tester);
      await tester.tap(find.text('Choose backup file'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'wrong');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Wrong passphrase, or the file is damaged.'),
        findsOneWidget,
      );
      expect(app.location, Routes.setupRestore);
    });

    testWidgets('cancelling the picker keeps the screen as it was', (
      tester,
    ) async {
      final app = await openRestore(tester);
      app.env.filePick.next = null;
      await tester.tap(find.text('Choose backup file'));
      await tester.pumpAndSettle();
      expect(find.text('No file chosen'), findsOneWidget);
    });

    testWidgets('a good passphrase restores and leaves the screen', (
      tester,
    ) async {
      final app = await openRestore(tester);
      app.env.filePick.next = const PickedFile(
        name: 'my.sgbackup',
        bytes: [9, 9, 9],
      );
      await tester.tap(find.text('Choose backup file'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'correct horse');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore').last);
      await tester.pumpAndSettle();

      expect(app.location, isNot(Routes.setupRestore));
    });

    testWidgets('the back arrow returns to the language step', (tester) async {
      final app = await openRestore(tester);
      await tester.tap(find.bySemanticsLabel('Choose a language'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.setupLanguage);
    });
  });
}
