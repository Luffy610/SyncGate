import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/app/providers.dart';

var _idCounter = 0;

/// Unique-enough IDs for events created in the app. The real data layer
/// issues UUIDv7s; this is only used with the in-memory fakes.
String newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

/// A mark that was stored.
class Marked {
  const new({required this.worker, required this.event});

  final Worker worker;
  final AttendanceEvent event;
}

/// Face match at the gate → one stored event (frontend plan §6.1).
///
/// The event is written before this returns, so the confirmation the gate
/// shows afterwards is never ahead of storage (NFR-REL-02). A repeat mark
/// inside the cooldown stores nothing and returns [AlreadyMarked].
class MarkAttendance {
  const new({
    required this.workers,
    required this.attendance,
    required this.shifts,
    required this.settings,
    required this.clock,
  });

  final WorkerRepository workers;
  final AttendanceRepository attendance;
  final ShiftRepository shifts;
  final SettingsRepository settings;
  final ClockService clock;

  Future<Result<Marked, Failure>> call(String workerId) async {
    final worker = await workers.byId(workerId);
    if (worker == null || !worker.active) return const Result.err(NotFound());

    final now = clock.now();
    final last = await attendance.lastEvent(workerId);
    final cooldown = Duration(seconds: (await settings.load()).cooldownSeconds);
    if (AttendanceRules.inCooldown(last, now, cooldown: cooldown)) {
      return Result.err(AlreadyMarked(at: last!.at, direction: last.direction));
    }

    final direction = AttendanceRules.nextDirection(last, now);
    final shift = (await shifts.all())
        .where((s) => s.id == worker.shiftId)
        .firstOrNull;
    final onTime =
        direction != Direction.checkIn ||
        shift == null ||
        AttendanceRules.isOnTime(shift, now);
    final event = AttendanceEvent(
      id: newId('ev'),
      workerId: worker.id,
      at: now,
      direction: direction,
      method: MarkMethod.face,
      onTime: onTime,
    );
    await attendance.append(event);
    return Result.ok(Marked(worker: worker, event: event));
  }
}

/// Guard picks a worker from the list (ADR-0004 §3). Needs no PIN, requires
/// a reason, is capped at three a day and shows up in Exceptions.
class MarkManualAttendance {
  const new({
    required this.workers,
    required this.attendance,
    required this.exceptions,
    required this.audit,
    required this.clock,
  });

  final WorkerRepository workers;
  final AttendanceRepository attendance;
  final ExceptionRepository exceptions;
  final AuditLog audit;
  final ClockService clock;

  /// [actor] is who is at the gate: `G-02` for the guard, or an admin's
  /// name when made from Admin mode.
  Future<Result<Marked, Failure>> call({
    required String workerId,
    required ManualReason reason,
    required String actor,
  }) async {
    final worker = await workers.byId(workerId);
    if (worker == null) return const Result.err(NotFound());

    final now = clock.now();
    final today = await attendance.eventsBetween(
      AttendanceRules.startOfDay(now),
      AttendanceRules.startOfDay(now).add(const Duration(days: 1)),
    );
    if (TodayCalculator.manualEntryCount(today, workerId) >=
        AttendanceRules.manualEntryLimitPerDay) {
      return const Result.err(ManualLimitReached());
    }

    final last = await attendance.lastEvent(workerId);
    final direction = AttendanceRules.nextDirection(last, now);
    final event = AttendanceEvent(
      id: newId('ev'),
      workerId: worker.id,
      at: now,
      direction: direction,
      method: MarkMethod.manual,
      reason: reason.name,
      markedBy: actor,
    );
    await attendance.append(event);
    await exceptions.add(
      ExceptionRecord(
        id: newId('ex'),
        kind: ExceptionKind.manual,
        at: now,
        workerId: worker.id,
        eventId: event.id,
        actor: actor,
        reason: reason,
      ),
    );
    await audit.append(
      AuditEntry(
        at: now,
        actor: actor,
        action: 'attendance.manual',
        detail: '${worker.code} ${direction.name} ${reason.name}',
      ),
    );
    return Result.ok(Marked(worker: worker, event: event));
  }
}

final markAttendanceProvider = Provider<MarkAttendance>((ref) {
  return MarkAttendance(
    workers: ref.watch(workerRepositoryProvider),
    attendance: ref.watch(attendanceRepositoryProvider),
    shifts: ref.watch(shiftRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

final markManualAttendanceProvider = Provider<MarkManualAttendance>((ref) {
  return MarkManualAttendance(
    workers: ref.watch(workerRepositoryProvider),
    attendance: ref.watch(attendanceRepositoryProvider),
    exceptions: ref.watch(exceptionRepositoryProvider),
    audit: ref.watch(auditLogProvider),
    clock: ref.watch(clockProvider),
  );
});
