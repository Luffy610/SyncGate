import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/router.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/setup/licence_key_format.dart';

import 'support/test_app.dart';

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('licence key formatter', () {
    test('adds the prefix and dashes while typing', () {
      expect(LicenceKeyFormatter.format('4f7k'), 'SGT-4F7K-');
      expect(LicenceKeyFormatter.format('4f7k2q'), 'SGT-4F7K-2Q');
      expect(
        LicenceKeyFormatter.format('sgt4f7k2q9ma1b2'),
        'SGT-4F7K-2Q9M-A1B2',
      );
    });

    test('lets the user type the prefix', () {
      expect(LicenceKeyFormatter.format('s'), 'S');
      expect(LicenceKeyFormatter.format('sg'), 'SG');
      expect(LicenceKeyFormatter.format('SGT-'), 'SGT');
    });

    test('ignores extra characters and spaces', () {
      expect(
        LicenceKeyFormatter.format('SGT-4F7K-2Q9M-A1B2-9999'),
        'SGT-4F7K-2Q9M-A1B2',
      );
      expect(LicenceKeyFormatter.format(' 4f 7k '), 'SGT-4F7K-');
    });

    test('knows a complete key', () {
      expect(LicenceKeyFormatter.isComplete('SGT-4F7K-2Q9M-A1B2'), isTrue);
      expect(LicenceKeyFormatter.isComplete('SGT-4F7K-2Q9M'), isFalse);
    });

    test('backspace over a trailing dash is not undone', () {
      const formatter = LicenceKeyFormatter();
      const typed = TextEditingValue(text: 'SGT-4F7K-');
      final deleted = formatter.formatEditUpdate(
        typed,
        const TextEditingValue(text: 'SGT-4F7K'),
      );
      expect(deleted.text, 'SGT-4F7K');
    });
  });

  group('step 1 · language', () {
    testWidgets('lists six languages and marks the unfinished ones', (
      tester,
    ) async {
      await pumpApp(tester, freshInstall: true);

      expect(find.text('Choose a language'), findsOneWidget);
      expect(find.text('भाषा चुनें'), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsOneWidget);
      for (final name in ['हिन्दी', 'ગુજરાતી', 'தமிழ்', 'ਪੰਜਾਬੀ', 'मराठी']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      // English is both the native name and the English name.
      expect(find.text('English'), findsNWidgets(2));
      expect(find.textContaining('Coming soon'), findsNWidgets(4));
      expect(find.text('Continue · आगे बढ़ें'), findsOneWidget);
    });

    testWidgets('choosing Hindi switches the app language at once', (
      tester,
    ) async {
      final app = await pumpApp(tester, freshInstall: true);

      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      expect(find.text('चरण 1 / 6'), findsOneWidget);
      expect(find.text('आगे बढ़ें · Continue'), findsOneWidget);
      final saved = await app.env.backend.settingsRepo.load();
      expect(saved.language, AppLanguage.hi);
    });

    testWidgets('a language without strings only shows a message', (
      tester,
    ) async {
      final app = await pumpApp(tester, freshInstall: true);

      await tester.tap(find.text('ગુજરાતી'));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsOneWidget);
      final saved = await app.env.backend.settingsRepo.load();
      expect(saved.language, AppLanguage.en);
    });

    testWidgets('Continue moves to the licence step and remembers it', (
      tester,
    ) async {
      final app = await pumpApp(tester, freshInstall: true);
      await next(tester, 'Continue · आगे बढ़ें');

      expect(app.location, Routes.setupLicence);
      expect(app.mode, const SetupMode(2));
      expect((await app.env.backend.settingsRepo.load()).setupStep, 2);
    });
  });

  group('step 2 · licence', () {
    Future<TestApp> openLicence(WidgetTester tester) async {
      final app = await pumpApp(tester, freshInstall: true);
      await next(tester, 'Continue · आगे बढ़ें');
      return app;
    }

    testWidgets('shows the device check', (tester) async {
      await openLicence(tester);

      expect(find.text('Activate your licence'), findsOneWidget);
      expect(find.text('THIS DEVICE'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('8 MP'), findsOneWidget);
      expect(find.text('4 GB'), findsOneWidget);
      expect(find.text('Android 13'), findsOneWidget);
    });

    testWidgets('the key is formatted and Activate waits for a full key', (
      tester,
    ) async {
      await openLicence(tester);
      Finder activate() => find.widgetWithText(Opacity, 'Activate');

      await tester.enterText(find.byType(TextField), '4f7k2q');
      await tester.pump();
      expect(find.text('SGT-4F7K-2Q'), findsOneWidget);
      expect(tester.widget<Opacity>(activate().first).opacity, lessThan(1));

      await tester.enterText(find.byType(TextField), 'sgt4f7k2q9ma1b2');
      await tester.pump();
      expect(find.text('SGT-4F7K-2Q9M-A1B2'), findsOneWidget);
      expect(tester.widget<Opacity>(activate().first).opacity, 1);
    });

    testWidgets('activating moves on and stores the licence', (tester) async {
      final app = await openLicence(tester);

      await tester.enterText(find.byType(TextField), 'sgt4f7k2q9ma1b2');
      await tester.pump();
      await next(tester, 'Activate');

      expect(app.location, Routes.setupShift);
      final licence = await app.env.backend.licence.current();
      expect(licence.state, LicenceState.active);
      expect(licence.key, 'SGT-4F7K-2Q9M-A1B2');
    });

    testWidgets('scanning the invoice QR fills the key', (tester) async {
      await openLicence(tester);

      await tester.tap(find.text('Scan QR on invoice'));
      await tester.pumpAndSettle();

      expect(find.text('SGT-4F7K-2Q9M-A1B2'), findsOneWidget);
    });

    testWidgets('no internet offers the trial instead', (tester) async {
      final app = await openLicence(tester);

      await tester.enterText(find.byType(TextField), 'sgtnonet1234567');
      await tester.pump();
      await next(tester, 'Activate');

      expect(
        find.textContaining('No internet. Activation needs a connection'),
        findsOneWidget,
      );
      expect(app.location, Routes.setupLicence);

      await next(tester, 'Start trial instead');
      expect(app.location, Routes.setupShift);
      final licence = await app.env.backend.licence.current();
      expect(licence.state, LicenceState.trial);
    });

    testWidgets('the free trial starts without a key', (tester) async {
      final app = await openLicence(tester);

      await next(tester, 'No key yet? Start 30-day free trial');

      expect(app.location, Routes.setupShift);
      expect(
        (await app.env.backend.licence.current()).state,
        LicenceState.trial,
      );
    });

    testWidgets('back returns to the language step', (tester) async {
      final app = await openLicence(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(app.location, Routes.setupLanguage);
      // The furthest step is kept, so Continue goes forward again.
      expect(app.mode, const SetupMode(2));
    });
  });

  group('step 3 · first shift', () {
    Future<TestApp> openShift(WidgetTester tester) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 3),
      );
      expect(app.location, Routes.setupShift);
      return app;
    }

    testWidgets('starts from Day 06:00–14:00 with 10 minutes grace', (
      tester,
    ) async {
      await openShift(tester);

      expect(find.text('Set up your first shift'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
    });

    testWidgets('saves changes to the shift', (tester) async {
      final app = await openShift(tester);

      await tester.enterText(find.byType(TextField), 'General');
      await tester.tap(find.text('10 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await next(tester, 'Continue');

      expect(app.location, Routes.setupCamera);
      final shifts = await app.env.backend.shifts.all();
      expect(shifts.first.name, 'General');
      expect(shifts.first.graceMinutes, 15);
    });

    testWidgets('picks a time with the stepper', (tester) async {
      final app = await openShift(tester);

      await tester.tap(find.text('06:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('hour down'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('05:00'), findsOneWidget);

      await next(tester, 'Continue');
      expect((await app.env.backend.shifts.all()).first.startMinute, 300);
    });

    testWidgets('a name is required and the times must differ', (tester) async {
      final app = await openShift(tester);

      await tester.enterText(find.byType(TextField), '');
      await next(tester, 'Continue');
      expect(find.text('Give the shift a name.'), findsOneWidget);
      expect(app.location, Routes.setupShift);

      await tester.enterText(find.byType(TextField), 'Day');
      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.bySemanticsLabel('hour down'));
        await tester.pump();
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await next(tester, 'Continue');
      expect(
        find.text("Start and end can't be the same time."),
        findsOneWidget,
      );
    });

    testWidgets('a night shift is described as ending the next day', (
      tester,
    ) async {
      await openShift(tester);

      await tester.tap(find.text('14:00'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.bySemanticsLabel('hour down'));
        await tester.pump();
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('Ends the next day'), findsOneWidget);
    });
  });

  group('step 4 · camera and light', () {
    testWidgets('warns about low light, then passes after checking again', (
      tester,
    ) async {
      await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 4),
      );

      expect(find.text('Check camera & light'), findsOneWidget);
      expect(find.text('Live preview'), findsOneWidget);
      expect(find.text('Light low · 42 lux'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(
        find.textContaining('Switch on a tube light near the gate'),
        findsOneWidget,
      );
      expect(find.text('Clean'), findsOneWidget);
      expect(find.text('Good at 60 cm'), findsOneWidget);

      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text('Light good · 240 lux'), findsOneWidget);
      expect(find.text('Light low · 42 lux'), findsNothing);
    });

    testWidgets('the fill light switch is saved', (tester) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 4),
      );

      await tester.tap(find.byType(SgSwitch));
      await tester.pumpAndSettle();
      expect(
        (await app.env.backend.settingsRepo.load()).screenFillLight,
        isFalse,
      );
    });

    testWidgets('Continue works even with a warning and stops the preview', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 4),
      );

      await next(tester, 'Continue');
      expect(app.location, Routes.setupKiosk);
      expect(app.env.cameraCheck.running, isFalse);
    });
  });

  group('step 5 · pin to the screen', () {
    testWidgets('Android: pin now flips the status and offers Continue', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 5),
      );

      expect(find.text('Pin SyncGate to the screen'), findsOneWidget);
      expect(find.text('App pinning off'), findsOneWidget);
      expect(
        find.text('Open Settings › Security › App pinning'),
        findsOneWidget,
      );

      await tester.tap(find.text('Pin SyncGate now'));
      await tester.pumpAndSettle();
      expect(find.text('App pinned'), findsOneWidget);
      expect(find.text('Pin SyncGate now'), findsNothing);

      await next(tester, 'Continue');
      expect(app.location, Routes.setupOwner);
    });

    testWidgets('Android: Open Settings goes to the OS', (tester) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 5),
      );
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(app.env.kiosk.settingsOpened, 1);
    });

    testWidgets('iOS: shows the Guided Access steps', (tester) async {
      await pumpApp(
        tester,
        freshInstall: true,
        platform: TargetPlatform.iOS,
        settings: const AppSettings(setupStep: 5),
      );

      expect(find.text('Guided Access off'), findsOneWidget);
      expect(
        find.text('Open Settings › Accessibility › Guided Access'),
        findsOneWidget,
      );
      expect(
        find.text('Triple-click the side button and tap Start'),
        findsOneWidget,
      );
      expect(find.text('Pin SyncGate now'), findsNothing);
    });

    testWidgets('can be skipped, the gate will warn instead', (tester) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 5),
      );
      await next(tester, 'Skip for now');
      expect(app.location, Routes.setupOwner);
      expect(app.env.kiosk.settingsOpened, 0);
    });
  });

  group('step 6 · owner PIN', () {
    Future<TestApp> openOwner(WidgetTester tester) => pumpApp(
      tester,
      freshInstall: true,
      settings: const AppSettings(setupStep: 6),
    );

    testWidgets('create, confirm, then show the recovery code once', (
      tester,
    ) async {
      final app = await openOwner(tester);
      expect(find.text('Create your owner PIN'), findsOneWidget);

      await tapDigits(tester, '482915');
      expect(find.text('Enter the PIN again'), findsOneWidget);
      await tapDigits(tester, '482915');

      expect(find.text('Write down your recovery code'), findsOneWidget);
      expect(find.byKey(const ValueKey('recovery-code')), findsOneWidget);
      expect(find.text('KX7M-4PQ2-9TWD'), findsOneWidget);
      expect(await app.env.backend.users.hasOwner(), isTrue);
      final owner = await app.env.backend.users.verifyPin(Role.owner, '482915');
      expect(owner.isOk, isTrue);
    });

    testWidgets('Continue waits for "I\'ve written it down"', (tester) async {
      final app = await openOwner(tester);
      await tapDigits(tester, '482915');
      await tapDigits(tester, '482915');

      await tester.tap(find.text('Continue'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(app.location, Routes.setupOwner);

      await tester.tap(find.text("I've written it down"));
      await tester.pump();
      await next(tester, 'Continue');
      expect(app.location, Routes.setupFirstWorker);
      expect(app.mode, const SetupMode(7));
    });

    testWidgets('different PINs start again with a message', (tester) async {
      final app = await openOwner(tester);
      await tapDigits(tester, '482915');
      await tapDigits(tester, '111111');

      expect(find.text("The PINs don't match. Start again."), findsOneWidget);
      expect(find.text('Create your owner PIN'), findsOneWidget);
      expect(await app.env.backend.users.hasOwner(), isFalse);
    });

    testWidgets('backspace removes a digit', (tester) async {
      await openOwner(tester);
      await tester.tap(find.text('4'));
      await tester.tap(find.text('8'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      // 4, 9 entered: four digits to go, so still on the create step.
      await tapDigits(tester, '123');
      expect(find.text('Create your owner PIN'), findsOneWidget);
    });
  });

  group('step 6b · first worker', () {
    testWidgets('"Later" finishes setup and opens the gate', (tester) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 7),
      );
      expect(find.text('Enrol your first worker'), findsOneWidget);

      await next(tester, 'Later — go to the gate');

      expect(app.mode, isA<GateMode>());
      expect(app.location, Routes.gate);
      expect(
        (await app.env.backend.settingsRepo.load()).mode,
        AppModeKind.gate,
      );
      expect(
        app.env.backend.audit.entries.map((e) => e.action),
        contains('setup.completed'),
      );
    });

    testWidgets('"Enrol first worker" opens the enrolment form as owner', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 7),
      );
      await next(tester, 'Enrol first worker');

      expect(app.mode, isA<AdminMode>());
      expect(app.location, Routes.enrolDetails);
    });
  });

  group('wizard rules', () {
    testWidgets('a crash resumes at the last step reached', (tester) async {
      final app = await pumpApp(
        tester,
        freshInstall: true,
        settings: const AppSettings(setupStep: 4),
      );
      expect(app.location, Routes.setupCamera);
      expect(find.text('Step 4 of 6'), findsOneWidget);
    });

    testWidgets('later steps cannot be opened early', (tester) async {
      final app = await pumpApp(tester, freshInstall: true);
      app.container.read(routerProvider).go(Routes.setupOwner);
      await tester.pumpAndSettle();
      expect(app.location, Routes.setupLanguage);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('every step fits on ${platform.name} at ${scale}x', (
          tester,
        ) async {
          final app = await pumpApp(
            tester,
            freshInstall: true,
            platform: platform,
            textScale: scale,
          );
          for (var step = 1; step <= 7; step++) {
            await app.modeController.goToSetupStep(step);
            app.container.read(routerProvider).go(Routes.setupSteps[step - 1]);
            await tester.pumpAndSettle();
            expect(app.location, Routes.setupSteps[step - 1]);
          }
        });
      }
    }
  });
}
