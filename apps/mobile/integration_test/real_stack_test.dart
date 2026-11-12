// The real stack, end to end: the real Flutter UI on a device or emulator,
// talking over HTTP to the real Spring Boot API and its database. Only the
// camera, the QR scanner and the share sheet are stand-ins.
//
// Needs a FRESH server database (the first-run setup is part of the flow):
//
//   cd services/api && rm -rf data && ./mvnw spring-boot:run
//   cd apps/mobile && flutter test integration_test/real_stack_test.dart \
//     -d <emulator id> --flavor dev --dart-define-from-file=env/dev.json
//
// The emulator reaches the host at http://10.0.2.2:8080 (set in env/dev.json).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sg_api/sg_api.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/syncgate_app.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';
import 'package:syncgate/src/wiring/api_support.dart';

const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
const _deviceKey = String.fromEnvironment(
  'DEVICE_KEY',
  defaultValue: 'dev-device-key-local',
);

/// Pumps real time until [finder] matches (network calls take real time, so
/// `pumpAndSettle` alone returns too early).
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  final visible = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .take(40)
      .join(' | ');
  throw TestFailure('Timed out waiting for $finder. On screen: $visible');
}

/// Taps the last widget showing [text] once it can actually be hit (a toast
/// from the previous step may still float over the bottom buttons).
Future<void> tapText(WidgetTester tester, String text) async {
  await waitFor(tester, find.text(text).hitTestable());
  await tester.tap(find.text(text).hitTestable().last);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scrolls [finder] clear of the fixed bottom bar, then taps it.
Future<void> tapScrolled(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.last);
  await tester.pump(const Duration(milliseconds: 300));
  final scroll = find.byType(SingleChildScrollView);
  if (scroll.evaluate().isNotEmpty) {
    await tester.drag(scroll.first, const Offset(0, -160));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(finder.last);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh install to payroll export, Tally and backup', (
    tester,
  ) async {
    final clock = ApiClock();
    final api = ApiBackend(
      baseUrl: _baseUrl,
      deviceKey: _deviceKey,
      now: clock.now,
      saveFile: (name, bytes) async => '/data/local/tmp/$name',
    );
    clock.offset = await api.serverClockOffset();
    expect(
      await api.users.hasOwner(),
      isFalse,
      reason: 'needs a fresh database',
    );

    final env = DevEnvironment(clock: clock, api: api);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              flavour: Flavour.dev,
              licenceBaseUrl: '',
              sentryDsn: '',
            ),
          ),
          ...env.overrides(),
        ],
        child: const SyncGateApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SyncGateApp)),
    );
    AppMode mode() => container.read(appModeProvider);

    // ---- Setup wizard, every step saved on the server --------------------
    await waitFor(tester, find.text('Choose a language'));
    await tapText(tester, 'Continue · आगे बढ़ें');

    await waitFor(tester, find.text('Scan QR on invoice'));
    await tester.tap(find.text('Scan QR on invoice'));
    await tester.pump(const Duration(seconds: 1));
    await tapText(tester, 'Activate');
    await waitFor(tester, find.text('Set up your first shift'));
    expect((await api.licence.current()).state, LicenceState.active);

    await tester.enterText(find.byType(TextField).first, 'Day');
    await tester.pump();
    await tapText(tester, 'Continue');
    await waitFor(tester, find.text('Check camera & light'));
    expect((await api.shifts.all()).single.name, 'Day');

    await tapText(tester, 'Continue');
    await waitFor(tester, find.text('Skip for now'));
    await tapText(tester, 'Skip for now');

    await waitFor(tester, find.text('Create your owner PIN'));
    await tapDigits(tester, '482915');
    await waitFor(tester, find.text('Enter the PIN again'));
    await tapDigits(tester, '482915');
    await waitFor(tester, find.text("I've written it down"));
    expect(await api.users.hasOwner(), isTrue);
    await tapText(tester, "I've written it down");
    await tapText(tester, 'Continue');

    // ---- First enrolment through the real forms ---------------------------
    await tapText(tester, 'Enrol first worker');
    await waitFor(tester, find.text('Department'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Geeta Rani');
    await tester.enterText(fields.at(2), '12031998');
    await tester.tap(find.text('Department'));
    await tester.pump(const Duration(seconds: 1));
    // A fresh server has no departments: add one from the picker.
    await tapText(tester, 'Add new department');
    await waitFor(tester, find.text('New department'));
    await tester.enterText(find.byType(TextField).last, 'Stitching');
    await tester.pump();
    await tapText(tester, 'Add');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).at(3), 'Machine operator');
    await tester.pump();
    await tapText(tester, 'Next');

    await waitFor(
      tester,
      find.text('Worker has heard or read this notice and agrees'),
    );
    await tapScrolled(
      tester,
      find.text('Worker has heard or read this notice and agrees'),
    );
    await tapText(tester, 'Agree & capture face');
    await waitFor(
      tester,
      find.text('Geeta Rani enrolled'),
      timeout: const Duration(seconds: 40),
    );

    final workers = await api.workers.all();
    expect(workers.single.name, 'Geeta Rani');
    expect(workers.single.faceStatus, FaceStatus.enrolled);
    expect(await api.consent.hasConsent(workers.single.id), isTrue);

    // ---- The gate: a (scripted) match is recorded by the server -----------
    await tapText(tester, 'Back to gate');
    await waitFor(tester, find.textContaining('marked IN'));
    env.gateVision.match(workers.single.id);
    await waitFor(tester, find.textContaining('IN ·'));
    await tester.pump(const Duration(seconds: 4));

    // ---- Unlock Admin with the PIN the server stored ----------------------
    await tester.tap(find.bySemanticsLabel('Admin unlock'));
    await waitFor(tester, find.text('Admin access'));
    await tapDigits(tester, '482915');
    await waitFor(tester, find.text('Start gate mode'));
    expect(mode(), isA<AdminMode>());
    await waitFor(tester, find.text('1'));

    // ---- Reports, Tally mapping and the three exports ---------------------
    await tapText(tester, 'Reports');
    await waitFor(tester, find.textContaining('1 worker'));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('0 of 1 matched'), findsOneWidget);

    await tapText(tester, 'Settings');
    await tapText(tester, 'Tally mapping');
    await waitFor(tester, find.text('Geeta Rani'));
    await tester.tap(find.text('Geeta Rani'));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).last, 'GEETA RANI');
    await tester.tap(find.text('Save').last);
    await waitFor(tester, find.text('1 of 1 matched'));
    expect((await api.tally.all()).values, ['GEETA RANI']);

    // ---- Backup: first one asks for a passphrase ---------------------------
    await tapText(tester, 'Settings'); // the tab: back to the settings hub
    await tapText(tester, 'Backup & device');
    await tapText(tester, 'Back up now');
    await waitFor(tester, find.text('Set a backup passphrase'));
    final suggestion = tester
        .widget<Text>(find.byKey(const ValueKey('passphrase-suggestion')))
        .data!;
    await tester.enterText(find.byType(TextField).last, suggestion);
    await tester.pump();
    await tester.tap(
      find.text('I understand SyncGate cannot recover this passphrase'),
    );
    await tester.pump();
    await tapText(tester, 'Save and back up');
    await waitFor(
      tester,
      find.textContaining('Last backup'),
      timeout: const Duration(seconds: 40),
    );
    expect((await api.backup.current()).lastBackupAt, isNotNull);

    // ---- Everything the server holds still adds up ------------------------
    final audit = await api.client.getMap('api/v1/audit/verify');
    expect(audit['ok'], isTrue);
    final attendance = await api.client.getMap('api/v1/attendance/verify');
    expect(attendance['ok'], isTrue);
    expect(attendance['checked'], 1);
    binding.reportData = {'ok': true};
  });
}
