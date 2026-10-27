import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/router.dart';
import 'package:syncgate/src/app/routes.dart';

import 'support/test_app.dart';

Future<TestApp> openSettings(
  WidgetTester tester, {
  Role role = Role.owner,
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) async {
  final app = await pumpApp(tester, platform: platform, textScale: textScale);
  await app.signIn(role);
  await tester.tap(find.text('Settings').last);
  await tester.pumpAndSettle();
  expect(app.location, Routes.settings);
  return app;
}

Future<void> openPage(WidgetTester tester, String row) async {
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

void main() {
  group('hub', () {
    testWidgets('the owner sees everything', (tester) async {
      await openSettings(tester);
      expect(find.text('Signed in as Owner'), findsOneWidget);
      for (final row in [
        'Backup & device',
        'Users & PINs',
        'Shifts & rules',
        'Gate settings',
        'Tally mapping',
        'Language',
        'Privacy & DPDP pack',
        'About SyncGate',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
    });

    testWidgets('an admin does not get Backup or Users', (tester) async {
      final app = await openSettings(tester, role: Role.admin);
      expect(find.text('Signed in as Admin'), findsOneWidget);
      expect(find.text('Backup & device'), findsNothing);
      expect(find.text('Users & PINs'), findsNothing);
      expect(find.text('Shifts & rules'), findsOneWidget);

      app.container.read(routerProvider).go(Routes.settingsBackup);
      await tester.pumpAndSettle();
      expect(app.location, Routes.settings);
    });

    testWidgets('sub-pages go back to Settings', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'About SyncGate');
      expect(app.location, Routes.settingsAbout);
      await tester.tap(find.bySemanticsLabel('Settings').first);
      await tester.pumpAndSettle();
      expect(app.location, Routes.settings);
    });
  });

  group('backup & device', () {
    testWidgets('warns about the old backup and shows the licence', (
      tester,
    ) async {
      final app = await openSettings(tester);
      await app.env.backend.licence.startTrial();
      await openPage(tester, 'Backup & device');

      expect(find.text('Last backup 8 days ago'), findsOneWidget);
      expect(find.text('16-10-2026, 7:40 PM · Google Drive'), findsOneWidget);
      expect(find.text('Back up now'), findsOneWidget);
      expect(find.text('Auto backup to Google Drive'), findsOneWidget);
      expect(
        find.text('[OWNER’S GOOGLE ACCOUNT] · when online'),
        findsOneWidget,
      );
      expect(find.text('7 days'), findsOneWidget);
      expect(
        find.textContaining('Backups never include face codes'),
        findsOneWidget,
      );
      expect(find.text('Trial · to 23-11-2026'), findsOneWidget);
      expect(find.text('Move to a new phone'), findsOneWidget);
      expect(find.text('Report phone lost or stolen'), findsOneWidget);
    });

    testWidgets('the first backup asks for a passphrase', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Backup & device');

      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      expect(app.location, Routes.settingsPassphrase);
      expect(find.text('Set a backup passphrase'), findsOneWidget);

      final suggestion = tester
          .widget<Text>(find.byKey(const ValueKey('passphrase-suggestion')))
          .data!;
      expect(suggestion.split(' '), hasLength(4));

      // Wrong confirmation, no acknowledgement: cannot save.
      await tester.enterText(find.byType(TextField), 'something else');
      await tester.pump();
      expect(find.text("The passphrases don't match."), findsOneWidget);
      await tester.tap(find.text('Save and back up'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(app.location, Routes.settingsPassphrase);

      await tester.enterText(find.byType(TextField), suggestion);
      await tester.tap(
        find.text('I understand SyncGate cannot recover this passphrase'),
      );
      await tester.pump();
      await tester.tap(find.text('Save and back up'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Backing up…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(app.location, Routes.settingsBackup);
      expect(find.text('Backup saved'), findsOneWidget);
      expect(find.text('Last backup today'), findsOneWidget);
      expect(
        (await app.env.backend.settingsRepo.load()).backupPassphraseSet,
        isTrue,
      );
    });

    testWidgets('after that, Back up now just runs', (tester) async {
      final app = await openSettings(tester);
      final repo = app.env.backend.settingsRepo;
      await repo.save((await repo.load()).copyWith(backupPassphraseSet: true));
      await openPage(tester, 'Backup & device');

      await tester.tap(find.text('Back up now'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Backing up…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(app.location, Routes.settingsBackup);
      expect(find.text('Last backup today'), findsOneWidget);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('backup.manual'),
      );
    });

    testWidgets('"Save backup file" backs up and opens the share sheet', (
      tester,
    ) async {
      final app = await openSettings(tester);
      final repo = app.env.backend.settingsRepo;
      await repo.save((await repo.load()).copyWith(backupPassphraseSet: true));
      await openPage(tester, 'Backup & device');

      await tester.tap(find.text('Save backup file'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(app.env.share.shared, ['syncgate-backup.sgbackup']);
    });

    testWidgets('reminder days and auto backup are saved', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Backup & device');

      await tester.tap(find.text('Remind me after'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14 days'));
      await tester.pumpAndSettle();
      expect(find.text('14 days'), findsOneWidget);

      await tester.tap(find.byType(SgSwitch));
      await tester.pumpAndSettle();
      final settings = await app.env.backend.settingsRepo.load();
      expect(settings.remindBackupDays, 14);
      expect(settings.autoBackup, isFalse);
    });

    testWidgets('reporting the phone lost asks first and is audited', (
      tester,
    ) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Backup & device');

      await scrollTo(tester, find.text('Report phone lost or stolen'));
      await tester.tap(find.text('Report phone lost or stolen'));
      await tester.pumpAndSettle();
      expect(find.text('Report this phone lost or stolen?'), findsOneWidget);
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Reported. The licence will be released when this phone is online.',
        ),
        findsOneWidget,
      );
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('device.reportedLost'),
      );
    });

    testWidgets('moving to a new phone explains the steps first', (
      tester,
    ) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Backup & device');

      await scrollTo(tester, find.text('Move to a new phone'));
      await tester.tap(find.text('Move to a new phone').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Back up first, then install SyncGate'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back up and continue'));
      await tester.pumpAndSettle();
      // No passphrase yet, so that comes first.
      expect(app.location, Routes.settingsPassphrase);
    });
  });

  group('shifts', () {
    testWidgets('lists shifts and edits one', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Shifts & rules');

      expect(find.text('Day'), findsOneWidget);
      expect(find.text('06:00–14:00 · grace 10 min'), findsOneWidget);
      expect(find.text('22:00–06:00 · grace 10 min'), findsOneWidget);

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('Edit shift'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'General');
      await tester.pump();
      await tester.tap(find.text('10 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('06:00–14:00 · grace 20 min'), findsOneWidget);
      final shifts = await app.env.backend.shifts.all();
      expect(shifts.first.name, 'General');
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('shift.saved'),
      );
    });

    testWidgets('adds a new shift', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Shifts & rules');

      await tester.tap(find.text('Add a shift'));
      await tester.pumpAndSettle();
      expect(find.text('New shift'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Evening');
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(find.text('Evening'), findsOneWidget);
      expect(find.text('14:00–22:00 · grace 10 min'), findsOneWidget);
      expect(await app.env.backend.shifts.all(), hasLength(3));
    });

    testWidgets('a new shift needs a name', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Shifts & rules');
      await tester.tap(find.text('Add a shift'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('New shift'), findsOneWidget);
      expect(await app.env.backend.shifts.all(), hasLength(2));
    });
  });

  group('users & PINs', () {
    testWidgets('lists the three roles and changes a PIN', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Users & PINs');

      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Gate operator'), findsOneWidget);

      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      expect(find.text('Change PIN · Admin'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '654321');
      await tester.enterText(find.byType(TextField).at(1), '654320');
      await tester.pump();
      expect(find.text("The PINs don't match."), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), '654321');
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(find.text('PIN changed'), findsOneWidget);
      final result = await app.env.backend.users.verifyPin(
        Role.admin,
        '654321',
      );
      expect(result.isOk, isTrue);
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('user.pinChanged'),
      );
    });
  });

  group('Tally mapping', () {
    testWidgets('maps the one unmatched worker', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Tally mapping');

      expect(find.text('23 of 24 matched'), findsOneWidget);
      expect(find.text('To map'), findsOneWidget);

      await scrollTo(tester, find.text('Meena Kumari'));
      await tester.tap(find.text('Meena Kumari'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'MEENA K');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(find.text('24 of 24 matched'), findsOneWidget);
      expect(find.text('To map'), findsNothing);
      final match = await app.env.backend.export.tallyMatch();
      expect(match.matched, 24);
    });
  });

  group('language and gate settings', () {
    testWidgets('the language switches the whole app', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Language');

      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      expect(find.text('सेटिंग्स'), findsWidgets);
      expect(
        (await app.env.backend.settingsRepo.load()).language,
        AppLanguage.hi,
      );
    });

    testWidgets('the idle timeout is a setting that takes effect', (
      tester,
    ) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Gate settings');

      expect(find.text('2 minutes'), findsWidgets);
      await tester.tap(find.text('Return to gate after'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 minutes'));
      await tester.pumpAndSettle();
      expect((await app.env.backend.settingsRepo.load()).idleMinutes, 5);

      await tester.pump(const Duration(minutes: 4, seconds: 30));
      expect(app.location, Routes.settingsGate);
    });

    testWidgets('the 24-hour clock changes the Today header', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Gate settings');

      await tester.tap(find.text('24-hour clock'));
      await tester.pumpAndSettle();
      expect(
        (await app.env.backend.settingsRepo.load()).use24HourClock,
        isTrue,
      );

      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();
      expect(find.text('Sat, 24-10-2026 · 05:52'), findsOneWidget);
    });

    testWidgets('the cooldown and volume can be changed', (tester) async {
      final app = await openSettings(tester);
      await openPage(tester, 'Gate settings');

      await tester.tap(find.text('Repeat mark ignored for'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 minutes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice volume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low'));
      await tester.pumpAndSettle();

      final settings = await app.env.backend.settingsRepo.load();
      expect(settings.cooldownSeconds, 300);
      expect(settings.voiceVolume, 0.3);
    });
  });

  group('privacy and about', () {
    testWidgets('the privacy pack shows coverage', (tester) async {
      await openSettings(tester);
      await openPage(tester, 'Privacy & DPDP pack');

      expect(
        find.text('Version v0-draft · shown before every enrolment'),
        findsOneWidget,
      );
      expect(find.text('0 of 25 workers'), findsOneWidget);
      expect(find.text('24 on this phone only'), findsOneWidget);
      expect(find.text('[GRIEVANCE CONTACT — TBD]'), findsOneWidget);
    });

    testWidgets('about shows the version and build', (tester) async {
      await openSettings(tester);
      await openPage(tester, 'About SyncGate');

      expect(find.text('0.1.0 (1)'), findsOneWidget);
      expect(find.text('dev'), findsOneWidget);
      expect(find.text('On this phone only'), findsOneWidget);
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('fits on ${platform.name} at ${scale}x', (tester) async {
        await openSettings(tester, platform: platform, textScale: scale);
        await openPage(tester, 'Backup & device');
        expect(find.text('Last backup 8 days ago'), findsOneWidget);
      });
    }
  }
}
