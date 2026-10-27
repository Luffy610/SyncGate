import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/application/attendance_use_cases.dart';

/// Fixes a day with no OUT mark: appends a correction event, resolves the
/// exception and writes the audit entry (ADR-0011: nothing is edited).
class CorrectRecord {
  const new({
    required this.attendance,
    required this.exceptions,
    required this.audit,
    required this.workers,
    required this.clock,
  });

  final AttendanceRepository attendance;
  final ExceptionRepository exceptions;
  final AuditLog audit;
  final WorkerRepository workers;
  final ClockService clock;

  Future<Result<AttendanceEvent, Failure>> call({
    required ExceptionRecord exception,
    required DateTime outAt,
    required String reason,
    required String actor,
  }) async {
    final workerId = exception.workerId;
    final inAt = exception.inAt;
    if (workerId == null || inAt == null) {
      return const Result.err(NotFound());
    }
    if (!outAt.isAfter(inAt)) return const Result.err(InvalidCorrection());

    final event = AttendanceEvent(
      id: newId('ev'),
      workerId: workerId,
      at: outAt,
      direction: Direction.checkOut,
      method: MarkMethod.correction,
      reason: reason,
      markedBy: actor,
    );
    await attendance.append(event);
    await exceptions.resolve(exception.id);
    final worker = await workers.byId(workerId);
    await audit.append(
      AuditEntry(
        at: clock.now(),
        actor: actor,
        action: 'attendance.corrected',
        detail:
            '${worker?.code ?? workerId} OUT none → '
            '${outAt.hour.toString().padLeft(2, '0')}:'
            '${outAt.minute.toString().padLeft(2, '0')} ($reason)',
      ),
    );
    return Result.ok(event);
  }
}

/// "Mark reviewed" for exceptions that need no change to the record.
class ReviewException {
  const new({
    required this.exceptions,
    required this.audit,
    required this.clock,
  });

  final ExceptionRepository exceptions;
  final AuditLog audit;
  final ClockService clock;

  Future<void> call(ExceptionRecord exception, {required String actor}) async {
    await exceptions.resolve(exception.id);
    await audit.append(
      AuditEntry(
        at: clock.now(),
        actor: actor,
        action: 'exception.reviewed',
        detail: exception.kind.name,
      ),
    );
  }
}

final correctRecordProvider = Provider<CorrectRecord>((ref) {
  return CorrectRecord(
    attendance: ref.watch(attendanceRepositoryProvider),
    exceptions: ref.watch(exceptionRepositoryProvider),
    audit: ref.watch(auditLogProvider),
    workers: ref.watch(workerRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

final reviewExceptionProvider = Provider<ReviewException>((ref) {
  return ReviewException(
    exceptions: ref.watch(exceptionRepositoryProvider),
    audit: ref.watch(auditLogProvider),
    clock: ref.watch(clockProvider),
  );
});
