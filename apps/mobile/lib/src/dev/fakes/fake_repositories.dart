import 'dart:async';

import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/dev/fakes/reactive.dart';
import 'package:syncgate/src/dev/seed.dart';

class FakeSettingsRepository implements SettingsRepository {
  new([AppSettings initial = const AppSettings()]) : _state = Reactive(initial);

  final Reactive<AppSettings> _state;

  @override
  Future<AppSettings> load() async => _state.value;

  @override
  Stream<AppSettings> watch() => _state.watch();

  @override
  Future<void> save(AppSettings settings) async => _state.value = settings;
}

class FakeWorkerRepository implements WorkerRepository {
  new(DemoSeed seed)
    : _workers = Reactive(List.of(seed.workers)),
      _departments = List.of(DemoSeed.departments);

  final Reactive<List<Worker>> _workers;
  final List<String> _departments;
  var _next = 100;

  @override
  Stream<List<Worker>> watchAll() => _workers.watch();

  @override
  Future<List<Worker>> all() async => _workers.value;

  @override
  Future<Worker?> byId(String id) async =>
      _workers.value.where((w) => w.id == id).firstOrNull;

  @override
  Future<String> nextCode() async {
    final used = _workers.value
        .map((w) => int.tryParse(w.code.replaceAll(RegExp('[^0-9]'), '')) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return 'W-${(used + 1).toString().padLeft(4, '0')}';
  }

  @override
  Future<bool> isCodeUnique(String code, {String? exceptWorkerId}) async =>
      !_workers.value.any(
        (w) =>
            w.code.toLowerCase() == code.trim().toLowerCase() &&
            w.id != exceptWorkerId,
      );

  @override
  Future<Worker> add(NewWorker worker) async {
    final created = Worker(
      id: 'w-new-${_next++}',
      code: worker.code,
      name: worker.name,
      dateOfBirth: worker.dateOfBirth,
      department: worker.department,
      designation: worker.designation,
      shiftId: worker.shiftId,
      contractor: worker.contractor,
      phone: worker.phone,
      language: worker.language,
    );
    _workers.value = [..._workers.value, created];
    return created;
  }

  @override
  Future<void> update(Worker worker) async {
    _workers.value = [
      for (final w in _workers.value)
        if (w.id == worker.id) worker else w,
    ];
  }

  @override
  Future<void> setFaceStatus(String workerId, FaceStatus status) async {
    _workers.value = [
      for (final w in _workers.value)
        if (w.id == workerId) w.copyWith(faceStatus: status) else w,
    ];
  }

  @override
  Future<void> setActive(String workerId, {required bool active}) async {
    _workers.value = [
      for (final w in _workers.value)
        if (w.id == workerId) w.copyWith(active: active) else w,
    ];
  }

  @override
  Future<void> delete(String workerId) async {
    _workers.value = [
      for (final w in _workers.value)
        if (w.id != workerId) w,
    ];
  }

  @override
  Future<List<String>> departments() async => List.of(_departments);

  @override
  Future<void> addDepartment(String name) async {
    if (!_departments.contains(name)) _departments.add(name);
  }

  @override
  Future<List<String>> contractors() async => List.of(DemoSeed.contractors);
}

class FakeAttendanceRepository implements AttendanceRepository {
  new(DemoSeed seed) : _events = Reactive(List.of(seed.events));

  final Reactive<List<AttendanceEvent>> _events;

  @override
  Stream<List<AttendanceEvent>> watchDay(DateTime day) => _events.watch().map(
    (all) => all.where((e) => AttendanceRules.isSameDay(e.at, day)).toList(),
  );

  @override
  Future<List<AttendanceEvent>> eventsBetween(
    DateTime from,
    DateTime to,
  ) async => _events.value
      .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
      .toList();

  @override
  Future<AttendanceEvent?> lastEvent(String workerId) async {
    final mine = _events.value.where((e) => e.workerId == workerId).toList();
    if (mine.isEmpty) return null;
    return mine.reduce((a, b) => a.at.isAfter(b.at) ? a : b);
  }

  @override
  Future<void> append(AttendanceEvent event) async {
    _events.value = [..._events.value, event];
  }
}

class FakeExceptionRepository implements ExceptionRepository {
  new(DemoSeed seed) : _items = Reactive(List.of(seed.exceptions));

  final Reactive<List<ExceptionRecord>> _items;

  @override
  Stream<List<ExceptionRecord>> watchAll() => _items.watch();

  @override
  Future<List<ExceptionRecord>> all() async => _items.value;

  @override
  Future<void> add(ExceptionRecord record) async {
    _items.value = [..._items.value, record];
  }

  @override
  Future<void> resolve(String id) async {
    _items.value = [
      for (final e in _items.value)
        if (e.id == id) e.copyWith(resolved: true) else e,
    ];
  }
}

class FakeShiftRepository implements ShiftRepository {
  new() : _shifts = Reactive(const [DemoSeed.dayShift, DemoSeed.nightShift]);

  final Reactive<List<Shift>> _shifts;

  @override
  Stream<List<Shift>> watch() => _shifts.watch();

  @override
  Future<List<Shift>> all() async => _shifts.value;

  @override
  Future<void> save(Shift shift) async {
    final exists = _shifts.value.any((s) => s.id == shift.id);
    _shifts.value = exists
        ? [
            for (final s in _shifts.value)
              if (s.id == shift.id) shift else s,
          ]
        : [..._shifts.value, shift];
  }
}

/// In-memory users. PINs are compared as plain strings; the real
/// implementation hashes them with Argon2id (ADR-0004 §2).
class FakeUserRepository implements UserRepository {
  new({this.ownerExists = false}) {
    if (ownerExists) _pins['u-owner'] = DemoSeed.ownerPin;
    _pins['u-admin'] = DemoSeed.adminPin;
    _pins['u-gate'] = DemoSeed.operatorPin;
  }

  bool ownerExists;
  final _pins = <String, String>{};
  final _failures = <Role, int>{};
  final _lockedUntil = <Role, DateTime>{};
  String? _recovery;

  /// Injected so lockout timing follows the app clock.
  DateTime Function() now = DateTime.now;

  static const _users = [
    AppUser(id: 'u-owner', name: 'Owner', role: Role.owner),
    AppUser(id: 'u-admin', name: 'Admin', role: Role.admin),
    AppUser(id: 'u-gate', name: 'Gate operator', role: Role.gateOperator),
  ];

  AppUser _userFor(Role role) => _users.firstWhere((u) => u.role == role);

  @override
  Future<bool> hasOwner() async => ownerExists;

  @override
  Future<String> createOwner(String pin) async {
    ownerExists = true;
    _pins['u-owner'] = pin;
    _recovery = 'KX7M-4PQ2-9TWD';
    return _recovery!;
  }

  @override
  Future<Result<AppUser, Failure>> verifyPin(Role role, String pin) async {
    final user = _userFor(role);
    final until = _lockedUntil[role];
    if (until != null && now().isBefore(until)) {
      return Result.err(LockedOut(until.difference(now())));
    }
    if (_pins[user.id] == pin) {
      _failures[role] = 0;
      _lockedUntil.remove(role);
      return Result.ok(user);
    }
    final failures = (_failures[role] ?? 0) + 1;
    _failures[role] = failures;
    final lock = PinPolicy.lockoutAfter(failures);
    if (lock > Duration.zero) {
      _lockedUntil[role] = now().add(lock);
      return Result.err(WrongPin(attemptsLeft: 0, lockedFor: lock));
    }
    return Result.err(
      WrongPin(attemptsLeft: PinPolicy.freeAttempts - failures),
    );
  }

  @override
  Future<Result<void, Failure>> resetOwnerPin({
    required String recoveryCode,
    required String newPin,
  }) async {
    if (recoveryCode.trim().toUpperCase() != _recovery) {
      return const Result.err(NotAllowed());
    }
    _pins['u-owner'] = newPin;
    _failures[Role.owner] = 0;
    _lockedUntil.remove(Role.owner);
    return const Result.ok(null);
  }

  @override
  Future<List<AppUser>> users() async => _users;

  @override
  Future<void> setPin(String userId, String pin) async => _pins[userId] = pin;
}

class FakeConsentRepository implements ConsentRepository {
  final records =
      <
        ({
          String workerId,
          String version,
          AppLanguage language,
          String adminId,
        })
      >[];

  @override
  Future<void> record({
    required String workerId,
    required String noticeVersion,
    required AppLanguage language,
    required String adminId,
  }) async {
    records.add((
      workerId: workerId,
      version: noticeVersion,
      language: language,
      adminId: adminId,
    ));
  }

  @override
  Future<bool> hasConsent(String workerId) async =>
      records.any((r) => r.workerId == workerId);
}

class FakeAuditLog implements AuditLog {
  final _entries = Reactive<List<AuditEntry>>([]);

  @override
  Future<void> append(AuditEntry entry) async {
    _entries.value = [..._entries.value, entry];
  }

  @override
  Stream<List<AuditEntry>> watch() => _entries.watch();

  List<AuditEntry> get entries => _entries.value;
}

class FakeTallyMappingRepository implements TallyMappingRepository {
  new(DemoSeed seed)
    : _map = Reactive({
        for (final w in seed.workers)
          // One enrolled worker is left unmapped, like the design.
          if (w.faceStatus == FaceStatus.enrolled && w.id != 'w-0110')
            w.id: w.name.toUpperCase(),
      });

  final Reactive<Map<String, String>> _map;

  @override
  Stream<Map<String, String>> watch() => _map.watch();

  @override
  Future<Map<String, String>> all() async => _map.value;

  @override
  Future<void> set(String workerId, String tallyName) async {
    _map.value = {..._map.value, workerId: tallyName};
  }
}
