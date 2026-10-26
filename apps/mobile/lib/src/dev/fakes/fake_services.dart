import 'dart:async';

import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/dev/fakes/fake_repositories.dart';
import 'package:syncgate/src/dev/fakes/reactive.dart';
import 'package:syncgate/src/dev/seed.dart';

/// A clock that starts at a chosen moment and then runs in real time. The
/// debug panel can skip forward.
class DemoClock implements ClockService {
  new({DateTime? start}) : _start = start ?? DateTime(2026, 10, 24, 5, 52) {
    _watch.start();
  }

  final DateTime _start;
  final _watch = Stopwatch();
  Duration _skipped = Duration.zero;

  @override
  DateTime now() => _start.add(_watch.elapsed).add(_skipped);

  void advance(Duration by) => _skipped += by;
}

/// A clock that never moves; for tests.
class FixedClock implements ClockService {
  new(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

class RecordingVoiceService implements VoiceService {
  final calls = <String>[];

  @override
  Future<void> playEarcon(Earcon earcon) async =>
      calls.add('earcon:${earcon.name}');

  @override
  Future<void> playPhrase(Phrase phrase, String languageCode) async =>
      calls.add('phrase:${phrase.name}:$languageCode');

  @override
  Future<void> speakName(String name, String languageCode) async =>
      calls.add('name:$name:$languageCode');

  @override
  Future<void> readNotice(String text, String languageCode) async =>
      calls.add('notice:$languageCode');
}

class FakeDeviceCheckService implements DeviceCheckService {
  @override
  Future<DeviceInfo> check() async => const DeviceInfo(
    cameraMegapixels: 8,
    memoryGb: 4,
    systemName: 'Android 13',
  );
}

class RecordingScreenService implements ScreenService {
  bool keepAwake = false;
  bool dimmed = false;

  @override
  Future<void> setKeepAwake({required bool enabled}) async =>
      keepAwake = enabled;

  @override
  Future<void> setDimmed({required bool dimmed}) async => this.dimmed = dimmed;
}

class RecordingShareService implements ShareService {
  final shared = <String>[];

  @override
  Future<void> shareFile(String path, {String? text}) async => shared.add(path);
}

class FakeBiometricService implements BiometricService {
  new({this.kind = BiometricKind.fingerprint, this.succeeds = true});

  BiometricKind kind;
  bool succeeds;

  @override
  Future<BiometricKind> availableKind() async => kind;

  @override
  Future<bool> authenticate({required String reason}) async => succeeds;
}

/// Pretends to scan the demo invoice QR.
class FakeQrScanService implements QrScanService {
  String? result = 'SGT-4F7K-2Q9M-A1B2';

  @override
  Future<String?> scan() async => result;
}

class FakeKioskService implements KioskService {
  new([KioskState initial = KioskState.unlocked]) : _state = Reactive(initial);

  final Reactive<KioskState> _state;
  int settingsOpened = 0;

  @override
  Stream<KioskState> get state => _state.watch();

  /// Lets the debug panel flip the OS state.
  // ignore: use_setters_to_change_properties, reads better as a verb.
  void set(KioskState value) => _state.value = value;

  @override
  Future<void> startPinning() async => _state.value = KioskState.locked;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeBackupService implements BackupService {
  new(this._now)
    : _info = Reactive(
        BackupInfo(
          lastBackupAt: DateTime(2026, 10, 16, 19, 40),
          destination: 'Google Drive',
        ),
      );

  final DateTime Function() _now;
  final Reactive<BackupInfo> _info;

  @override
  Stream<BackupInfo> watch() => _info.watch();

  @override
  Future<BackupInfo> current() async => _info.value;

  @override
  Future<Result<BackupInfo, Failure>> backupNow() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _info.value = BackupInfo(lastBackupAt: _now(), destination: 'Google Drive');
    return Result.ok(_info.value);
  }
}

class FakeLicenceService implements LicenceService {
  new(this._now)
    : _status = Reactive(const LicenceStatus(state: LicenceState.none));

  final DateTime Function() _now;
  final Reactive<LicenceStatus> _status;

  static final _keyPattern = RegExp(
    r'^SGT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
  );

  @override
  Stream<LicenceStatus> watch() => _status.watch();

  @override
  Future<LicenceStatus> current() async => _status.value;

  @override
  Future<Result<LicenceStatus, Failure>> activate(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!_keyPattern.hasMatch(key)) {
      return const Result.err(InvalidLicenceKey());
    }
    if (key.replaceAll('-', '').contains('NONET')) {
      return const Result.err(NoInternet());
    }
    final now = _now();
    _status.value = LicenceStatus(
      state: LicenceState.active,
      key: key,
      expiresOn: DateTime(now.year + 1, now.month, now.day),
    );
    return Result.ok(_status.value);
  }

  @override
  Future<LicenceStatus> startTrial() async {
    final now = _now();
    _status.value = LicenceStatus(
      state: LicenceState.trial,
      expiresOn: now.add(const Duration(days: 30)),
    );
    return _status.value;
  }
}

class FakeReportService implements ReportService {
  new({
    required this.workers,
    required this.attendance,
    required this.exceptions,
    required this.shifts,
    required this.now,
  });

  final WorkerRepository workers;
  final AttendanceRepository attendance;
  final ExceptionRepository exceptions;
  final ShiftRepository shifts;
  final DateTime Function() now;

  Future<List<Worker>> _filtered(ReportFilter f) async {
    final all = await workers.all();
    return all
        .where(
          (w) =>
              w.active &&
              w.faceStatus == FaceStatus.enrolled &&
              (f.department == null || w.department == f.department) &&
              (f.shiftId == null || w.shiftId == f.shiftId) &&
              (f.contractor == null || w.contractor == f.contractor),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  int _lastCountedDay(DateTime month) {
    final today = now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    if (today.year == month.year && today.month == month.month) {
      return today.day;
    }
    return today.isBefore(month) ? 0 : daysInMonth;
  }

  @override
  int workingDays(DateTime month) {
    var count = 0;
    for (var d = 1; d <= _lastCountedDay(month); d++) {
      if (DateTime(month.year, month.month, d).weekday != DateTime.sunday) {
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<MusterRow>> monthly(ReportFilter filter) async {
    final month = DateTime(filter.month.year, filter.month.month);
    final events = await attendance.eventsBetween(
      month,
      DateTime(month.year, month.month + 1),
    );
    // No marks at all: the month was before SyncGate, so there is no muster.
    if (events.isEmpty) return const [];
    final open = (await exceptions.all())
        .where((e) => !e.resolved && e.workerId != null)
        .map((e) => e.workerId)
        .toSet();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final counted = _lastCountedDay(month);
    final rows = <MusterRow>[];

    for (final w in await _filtered(filter)) {
      final mine = events.where((e) => e.workerId == w.id).toList();
      var present = 0;
      var absent = 0;
      var late = 0;
      var overtime = 0.0;
      final days = <String>[];
      for (var d = 1; d <= daysInMonth; d++) {
        final day = DateTime(month.year, month.month, d);
        if (d > counted) {
          days.add('');
          continue;
        }
        if (day.weekday == DateTime.sunday) {
          days.add('WO');
          continue;
        }
        final dayEvents =
            mine.where((e) => AttendanceRules.isSameDay(e.at, day)).toList()
              ..sort((a, b) => a.at.compareTo(b.at));
        final ins = dayEvents.where((e) => e.direction == Direction.checkIn);
        if (ins.isEmpty) {
          // Today is not over: not absent yet.
          if (AttendanceRules.isSameDay(day, now())) {
            days.add('');
            continue;
          }
          absent++;
          days.add('A');
          continue;
        }
        present++;
        final first = ins.first;
        if (!first.onTime) {
          late++;
          days.add('L');
        } else {
          days.add('P');
        }
        final outs = dayEvents.where((e) => e.direction == Direction.checkOut);
        if (outs.isNotEmpty) {
          final hours = outs.last.at.difference(first.at).inMinutes / 60;
          if (hours > 8) overtime += hours - 8;
        }
      }
      rows.add(
        MusterRow(
          worker: w,
          present: present,
          absent: absent,
          late: late,
          overtimeHours: double.parse(overtime.toStringAsFixed(1)),
          hasOpenExceptions: open.contains(w.id),
          days: days,
        ),
      );
    }
    return rows;
  }

  @override
  Future<List<DailyRow>> daily(DateTime day) async {
    final events = await attendance.eventsBetween(
      AttendanceRules.startOfDay(day),
      AttendanceRules.startOfDay(day).add(const Duration(days: 1)),
    );
    final open = (await exceptions.all())
        .where((e) => !e.resolved && e.workerId != null)
        .map((e) => e.workerId)
        .toSet();
    final rows = <DailyRow>[];
    for (final w in await _filtered(ReportFilter(month: day))) {
      final mine = events.where((e) => e.workerId == w.id).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      final ins = mine.where((e) => e.direction == Direction.checkIn);
      final outs = mine.where((e) => e.direction == Direction.checkOut);
      final status = ins.isEmpty ? 'A' : (ins.first.onTime ? 'P' : 'L');
      rows.add(
        DailyRow(
          worker: w,
          inAt: ins.isEmpty ? null : ins.first.at,
          outAt: outs.isEmpty ? null : outs.last.at,
          status: status,
          flagged: open.contains(w.id),
        ),
      );
    }
    return rows;
  }
}

class FakeExportService implements ExportService {
  new(this.reports, this.workers, this.tally);

  final ReportService reports;
  final WorkerRepository workers;
  final TallyMappingRepository tally;
  final exports = <(ExportFormat, ReportFilter)>[];

  @override
  Future<Result<ExportResult, Failure>> export(
    ExportFormat format,
    ReportFilter filter,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final rows = await reports.monthly(filter);
    exports.add((format, filter));
    final ext = format == ExportFormat.excel ? 'xlsx' : 'xml';
    final month =
        '${filter.month.year}-${filter.month.month.toString().padLeft(2, '0')}';
    return Result.ok(
      ExportResult(path: 'syncgate-muster-$month.$ext', rows: rows.length),
    );
  }

  @override
  Future<({int matched, int total})> tallyMatch() async {
    final enrolled = (await workers.all())
        .where((w) => w.active && w.faceStatus == FaceStatus.enrolled)
        .toList();
    final map = await tally.all();
    final matched = enrolled.where((w) => map.containsKey(w.id)).length;
    return (matched: matched, total: enrolled.length);
  }
}

/// Helper so dev wiring can build everything from one seed.
class DemoBackend {
  new({
    required bool ownerExists,
    DemoSeed? seed,
    AppSettings? settings,
    ClockService? clock,
  }) : seed = seed ?? DemoSeed(),
       clock = clock ?? DemoClock() {
    settingsRepo = FakeSettingsRepository(settings ?? const AppSettings());
    workers = FakeWorkerRepository(this.seed);
    attendance = FakeAttendanceRepository(this.seed);
    exceptions = FakeExceptionRepository(this.seed);
    shifts = FakeShiftRepository();
    users = FakeUserRepository(ownerExists: ownerExists)..now = this.clock.now;
    consent = FakeConsentRepository();
    audit = FakeAuditLog();
    backup = FakeBackupService(this.clock.now);
    licence = FakeLicenceService(this.clock.now);
    reports = FakeReportService(
      workers: workers,
      attendance: attendance,
      exceptions: exceptions,
      shifts: shifts,
      now: this.clock.now,
    );
    tally = FakeTallyMappingRepository(this.seed);
    export = FakeExportService(reports, workers, tally);
  }

  final DemoSeed seed;
  final ClockService clock;
  late final FakeSettingsRepository settingsRepo;
  late final FakeWorkerRepository workers;
  late final FakeAttendanceRepository attendance;
  late final FakeExceptionRepository exceptions;
  late final FakeShiftRepository shifts;
  late final FakeUserRepository users;
  late final FakeConsentRepository consent;
  late final FakeAuditLog audit;
  late final FakeBackupService backup;
  late final FakeLicenceService licence;
  late final FakeReportService reports;
  late final FakeTallyMappingRepository tally;
  late final FakeExportService export;
}
