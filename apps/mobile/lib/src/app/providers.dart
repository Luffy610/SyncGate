import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_vision/sg_vision.dart';

/// Interfaces the UI depends on (frontend plan §3.2). Each is bound in
/// `main_<flavour>.dart`: fakes in dev, real implementations later (F6).
Provider<T> _unwired<T>() => Provider<T>(
  (ref) => throw UnimplementedError(
    '$T is not wired for this flavour yet (frontend plan step F6).',
  ),
);

final Provider<ClockService> clockProvider = _unwired<ClockService>();
final Provider<SettingsRepository> settingsRepositoryProvider =
    _unwired<SettingsRepository>();
final Provider<WorkerRepository> workerRepositoryProvider =
    _unwired<WorkerRepository>();
final Provider<AttendanceRepository> attendanceRepositoryProvider =
    _unwired<AttendanceRepository>();
final Provider<ExceptionRepository> exceptionRepositoryProvider =
    _unwired<ExceptionRepository>();
final Provider<ShiftRepository> shiftRepositoryProvider =
    _unwired<ShiftRepository>();
final Provider<UserRepository> userRepositoryProvider =
    _unwired<UserRepository>();
final Provider<ConsentRepository> consentRepositoryProvider =
    _unwired<ConsentRepository>();
final Provider<AuditLog> auditLogProvider = _unwired<AuditLog>();
final Provider<ReportService> reportServiceProvider = _unwired<ReportService>();
final Provider<TallyMappingRepository> tallyMappingProvider =
    _unwired<TallyMappingRepository>();
final Provider<ExportService> exportServiceProvider = _unwired<ExportService>();
final Provider<BackupService> backupServiceProvider = _unwired<BackupService>();
final Provider<LicenceService> licenceServiceProvider =
    _unwired<LicenceService>();

final Provider<GateVisionService> gateVisionProvider =
    _unwired<GateVisionService>();
final Provider<EnrolmentCaptureService> enrolmentCaptureProvider =
    _unwired<EnrolmentCaptureService>();
final Provider<CameraCheckService> cameraCheckProvider =
    _unwired<CameraCheckService>();

final Provider<KioskService> kioskProvider = _unwired<KioskService>();
final Provider<VoiceService> voiceProvider = _unwired<VoiceService>();
final Provider<DeviceCheckService> deviceCheckProvider =
    _unwired<DeviceCheckService>();
final Provider<ScreenService> screenProvider = _unwired<ScreenService>();
final Provider<ShareService> shareProvider = _unwired<ShareService>();
final Provider<BiometricService> biometricProvider =
    _unwired<BiometricService>();
final Provider<QrScanService> qrScanProvider = _unwired<QrScanService>();

/// Dev flavour only: builds the debug panel opened by long-pressing the gate
/// logo. `null` in staging and prod.
final debugPanelBuilderProvider = Provider<WidgetBuilder?>((ref) => null);

/// How often the app clock ticks. Tests override this with [Duration.zero]
/// so `pumpAndSettle` can finish.
final tickPeriodProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
);

/// The current time from the app clock, ticking while the app is open.
final tickProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  final period = ref.watch(tickPeriodProvider);
  if (period == Duration.zero) return Stream.value(clock.now());
  return Stream.periodic(period, (_) => clock.now()).startWith(clock.now());
});

extension<T> on Stream<T> {
  Stream<T> startWith(T first) async* {
    yield first;
    yield* this;
  }
}

final nowProvider = Provider<DateTime>((ref) {
  return ref.watch(tickProvider).value ?? ref.watch(clockProvider).now();
});

/// Midnight of the current day; changes only when the date does.
final todayProvider = Provider<DateTime>((ref) {
  final day = ref.watch(
    nowProvider.select(
      (now) => AttendanceRules.startOfDay(now).millisecondsSinceEpoch,
    ),
  );
  return DateTime.fromMillisecondsSinceEpoch(day);
});

final settingsProvider = StreamProvider<AppSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watch();
});

final workersProvider = StreamProvider<List<Worker>>((ref) {
  return ref.watch(workerRepositoryProvider).watchAll();
});

final shiftsProvider = StreamProvider<List<Shift>>((ref) {
  return ref.watch(shiftRepositoryProvider).watch();
});

final todayEventsProvider = StreamProvider<List<AttendanceEvent>>((ref) {
  final day = ref.watch(todayProvider);
  return ref.watch(attendanceRepositoryProvider).watchDay(day);
});

final exceptionsProvider = StreamProvider<List<ExceptionRecord>>((ref) {
  return ref.watch(exceptionRepositoryProvider).watchAll();
});

/// Exceptions that still need a look.
final openExceptionsProvider = Provider<List<ExceptionRecord>>((ref) {
  final all = ref.watch(exceptionsProvider).value ?? const <ExceptionRecord>[];
  return all.where((e) => !e.resolved).toList();
});

final kioskStateProvider = StreamProvider<KioskState>((ref) {
  return ref.watch(kioskProvider).state;
});

final backupInfoProvider = StreamProvider<BackupInfo>((ref) {
  return ref.watch(backupServiceProvider).watch();
});

final licenceStatusProvider = StreamProvider<LicenceStatus>((ref) {
  return ref.watch(licenceServiceProvider).watch();
});

/// Overrides the platform look (iOS / Android) from the debug panel.
class LookController extends Notifier<TargetPlatform?> {
  @override
  TargetPlatform? build() => null;

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void set(TargetPlatform? platform) => state = platform;
}

final lookProvider = NotifierProvider<LookController, TargetPlatform?>(
  LookController.new,
);

/// The platform the UI is drawn for.
final platformProvider = Provider<TargetPlatform>((ref) {
  return ref.watch(lookProvider) ?? defaultTargetPlatform;
});

/// While above zero the idle timer is held (e.g. face capture, sharing).
class IdleHold extends Notifier<int> {
  @override
  int build() => 0;

  void hold() {
    if (ref.mounted) state++;
  }

  void release() {
    // Called from dispose callbacks that can outlive the container.
    if (ref.mounted && state > 0) state--;
  }
}

final idleHoldProvider = NotifierProvider<IdleHold, int>(IdleHold.new);
