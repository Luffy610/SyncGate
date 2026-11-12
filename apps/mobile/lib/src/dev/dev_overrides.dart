import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sg_api/sg_api.dart' show ApiBackend;
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/dev/debug_panel.dart';
import 'package:syncgate/src/dev/fakes/fake_services.dart';
import 'package:syncgate/src/dev/fakes/fake_vision.dart';

/// Everything the dev flavour runs against: in-memory repositories seeded
/// with the demo data and a scripted fake camera (frontend plan §3.2).
///
/// Only `main_dev.dart` may import `src/dev/`, so none of this is compiled
/// into staging or prod (checked by `tools/check_imports.dart`).
class DevEnvironment {
  new({bool freshInstall = true, ClockService? clock, this.api})
    : backend = DemoBackend(
        ownerExists: !freshInstall,
        clock: clock,
        settings: freshInstall
            ? const AppSettings()
            : const AppSettings(mode: AppModeKind.gate, setupStep: 7),
      ) {
    gateVision = FakeGateVisionService();
    enrolment = FakeEnrolmentCaptureService();
    cameraCheck = FakeCameraCheckService();
    kiosk = FakeKioskService();
    voice = RecordingVoiceService();
    screen = RecordingScreenService();
    share = RecordingShareService();
    biometric = FakeBiometricService();
    qr = FakeQrScanService();
    device = FakeDeviceCheckService();
  }

  /// When set, the data layer is the real API instead of the demo fakes.
  final ApiBackend? api;

  final DemoBackend backend;
  late final FakeGateVisionService gateVision;
  late final FakeEnrolmentCaptureService enrolment;
  late final FakeCameraCheckService cameraCheck;
  late final FakeKioskService kiosk;
  late final RecordingVoiceService voice;
  late final RecordingScreenService screen;
  late final RecordingShareService share;
  late final FakeBiometricService biometric;
  late final FakeQrScanService qr;
  late final FakeDeviceCheckService device;

  List<Override> overrides() => [
    devEnvironmentProvider.overrideWithValue(this),
    debugPanelBuilderProvider.overrideWithValue((_) => const DebugPanel()),
    clockProvider.overrideWithValue(backend.clock),
    ..._data(),
    gateVisionProvider.overrideWithValue(gateVision),
    enrolmentCaptureProvider.overrideWithValue(enrolment),
    cameraCheckProvider.overrideWithValue(cameraCheck),
    kioskProvider.overrideWithValue(kiosk),
    voiceProvider.overrideWithValue(voice),
    deviceCheckProvider.overrideWithValue(device),
    screenProvider.overrideWithValue(screen),
    shareProvider.overrideWithValue(share),
    biometricProvider.overrideWithValue(biometric),
    qrScanProvider.overrideWithValue(qr),
  ];

  /// The data layer: the Spring Boot API when [api] is set, otherwise the
  /// in-memory demo repositories.
  List<Override> _data() {
    final remote = api;
    if (remote != null) {
      return [
        settingsRepositoryProvider.overrideWithValue(remote.settings),
        workerRepositoryProvider.overrideWithValue(remote.workers),
        attendanceRepositoryProvider.overrideWithValue(remote.attendance),
        exceptionRepositoryProvider.overrideWithValue(remote.exceptions),
        shiftRepositoryProvider.overrideWithValue(remote.shifts),
        userRepositoryProvider.overrideWithValue(remote.users),
        consentRepositoryProvider.overrideWithValue(remote.consent),
        auditLogProvider.overrideWithValue(remote.audit),
        reportServiceProvider.overrideWithValue(remote.reports),
        exportServiceProvider.overrideWithValue(remote.export),
        tallyMappingProvider.overrideWithValue(remote.tally),
        backupServiceProvider.overrideWithValue(remote.backup),
        licenceServiceProvider.overrideWithValue(remote.licence),
      ];
    }
    return [
      settingsRepositoryProvider.overrideWithValue(backend.settingsRepo),
      workerRepositoryProvider.overrideWithValue(backend.workers),
      attendanceRepositoryProvider.overrideWithValue(backend.attendance),
      exceptionRepositoryProvider.overrideWithValue(backend.exceptions),
      shiftRepositoryProvider.overrideWithValue(backend.shifts),
      userRepositoryProvider.overrideWithValue(backend.users),
      consentRepositoryProvider.overrideWithValue(backend.consent),
      auditLogProvider.overrideWithValue(backend.audit),
      reportServiceProvider.overrideWithValue(backend.reports),
      exportServiceProvider.overrideWithValue(backend.export),
      tallyMappingProvider.overrideWithValue(backend.tally),
      backupServiceProvider.overrideWithValue(backend.backup),
      licenceServiceProvider.overrideWithValue(backend.licence),
    ];
  }
}

/// Provider overrides for `main_dev.dart`. Set `--dart-define=DEV_START=gate`
/// to skip the setup wizard (owner PIN 123456).
List<Override> devOverrides({bool freshInstall = true}) =>
    DevEnvironment(freshInstall: freshInstall).overrides();

/// Provider overrides for `main_dev_api.dart`: the same scripted camera and
/// platform fakes, but every repository and service talks to the Spring Boot
/// API, and time comes from the server.
List<Override> devApiOverrides(ApiBackend api, ClockService clock) =>
    DevEnvironment(clock: clock, api: api).overrides();
