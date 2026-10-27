import 'package:sg_domain/src/attendance_rules.dart';
import 'package:sg_domain/src/entities.dart';

/// Where a worker stands today (Workers list, gate footer).
sealed class WorkerDayStatus {
  const new();
}

final class StatusNeedsFace extends WorkerDayStatus {
  const new();
}

final class StatusNotIn extends WorkerDayStatus {
  const new();
}

final class StatusOnLeave extends WorkerDayStatus {
  const new();
}

final class StatusIn extends WorkerDayStatus {
  const new(this.at);

  final DateTime at;
}

final class StatusOut extends WorkerDayStatus {
  const new(this.at);

  final DateTime at;
}

/// Pure calculations behind the Today screen, the gate footer and the
/// Workers list. The same code runs against fakes and the real database.
abstract final class TodayCalculator {
  static List<AttendanceEvent> _forWorker(
    List<AttendanceEvent> events,
    String workerId,
  ) =>
      events.where((e) => e.workerId == workerId).toList()
        ..sort((a, b) => a.at.compareTo(b.at));

  /// Workers who should be marked today: active, enrolled, not on leave.
  static bool isExpected(Worker w) =>
      w.active && w.faceStatus == FaceStatus.enrolled && !w.onLeave;

  static WorkerDayStatus statusOf(Worker w, List<AttendanceEvent> events) {
    if (w.faceStatus == FaceStatus.needsFace) return const StatusNeedsFace();
    final mine = _forWorker(events, w.id);
    if (mine.isNotEmpty) {
      final last = mine.last;
      return last.direction == Direction.checkIn
          ? StatusIn(last.at)
          : StatusOut(last.at);
    }
    return w.onLeave ? const StatusOnLeave() : const StatusNotIn();
  }

  static bool hasMarkedIn(List<AttendanceEvent> events, String workerId) =>
      events.any(
        (e) => e.workerId == workerId && e.direction == Direction.checkIn,
      );

  /// Expected workers for the gate footer ("18 of 24 marked IN").
  static ({int marked, int expected}) gateProgress({
    required List<Worker> workers,
    required List<AttendanceEvent> events,
    String? shiftId,
  }) {
    final expected = workers
        .where(
          (w) => isExpected(w) && (shiftId == null || w.shiftId == shiftId),
        )
        .toList();
    final marked = expected.where((w) => hasMarkedIn(events, w.id)).length;
    return (marked: marked, expected: expected.length);
  }

  /// The most recent mark of the day, for the gate footer's last-mark row.
  static AttendanceEvent? lastMark(List<AttendanceEvent> events) {
    if (events.isEmpty) return null;
    return events.reduce((a, b) => a.at.isAfter(b.at) ? a : b);
  }

  static TodaySummary summary({
    required List<Worker> workers,
    required List<AttendanceEvent> events,
    required List<Shift> shifts,
    required DateTime now,
    String? shiftId,
  }) {
    final inShift = workers
        .where((w) => w.active && (shiftId == null || w.shiftId == shiftId))
        .toList();
    final expected = inShift.where(isExpected).toList();
    final onLeave = inShift.where((w) => w.onLeave).length;

    var present = 0;
    var late = 0;
    var onPremises = 0;
    var wentOut = 0;
    var absent = 0;
    final minute = now.hour * 60 + now.minute;
    for (final w in expected) {
      final mine = _forWorker(events, w.id);
      final ins = mine.where((e) => e.direction == Direction.checkIn).toList();
      if (ins.isNotEmpty) {
        present++;
        if (!ins.first.onTime) late++;
        if (mine.last.direction == Direction.checkIn) {
          onPremises++;
        } else {
          wentOut++;
        }
      } else {
        final shift = shifts.where((s) => s.id == w.shiftId).firstOrNull;
        if (shift != null && !shift.crossesMidnight) {
          if (minute > shift.startMinute + shift.graceMinutes) absent++;
        } else if (shift != null && minute >= shift.endMinute) {
          if (minute > shift.startMinute + shift.graceMinutes) absent++;
        }
      }
    }

    final shift = shiftId == null
        ? shifts.firstOrNull
        : shifts.where((s) => s.id == shiftId).firstOrNull;
    final lateAt = shift == null
        ? '--:--'
        : _hhmm(shift.startMinute + shift.graceMinutes);
    return TodaySummary(
      expected: expected.length,
      present: present,
      absent: absent,
      onLeave: onLeave,
      late: late,
      onPremises: onPremises,
      wentOut: wentOut,
      lateAfterLabel: lateAt,
    );
  }

  static String _hhmm(int minuteOfDay) {
    final m = minuteOfDay % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Workers the guard can pick: expected workers with no mark yet today,
  /// plus anyone who is IN once their shift is about to end (needs OUT).
  static List<({Worker worker, Direction direction})> manualCandidates({
    required List<Worker> workers,
    required List<AttendanceEvent> events,
    required List<Shift> shifts,
    required DateTime now,
    String? shiftId,
  }) {
    final result = <({Worker worker, Direction direction})>[];
    final minute = now.hour * 60 + now.minute;
    for (final w in workers.where(
      (w) => isExpected(w) && (shiftId == null || w.shiftId == shiftId),
    )) {
      final shift = shifts.where((s) => s.id == w.shiftId).firstOrNull;
      final mine = _forWorker(events, w.id);
      // Only the shift that is running now can need a mark.
      if (mine.isEmpty && shift != null && !shift.isRunningAt(now)) continue;
      if (mine.isEmpty) {
        result.add((worker: w, direction: Direction.checkIn));
        continue;
      }
      final ending = shift != null && minute >= shift.endMinute - 60;
      if (ending && mine.last.direction == Direction.checkIn) {
        result.add((worker: w, direction: Direction.checkOut));
      }
    }
    result.sort((a, b) => a.worker.name.compareTo(b.worker.name));
    return result;
  }

  /// Manual entries already made for [workerId] on the day of [events].
  static int manualEntryCount(List<AttendanceEvent> events, String workerId) =>
      events
          .where((e) => e.workerId == workerId && e.method == MarkMethod.manual)
          .length;

  /// Whole days between two dates, ignoring time of day.
  static int daysAgo(DateTime from, DateTime to) =>
      AttendanceRules.startOfDay(to)
          .difference(AttendanceRules.startOfDay(from))
          .inDays;
}
