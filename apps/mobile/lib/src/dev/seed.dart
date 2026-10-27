import 'dart:math';

import 'package:sg_domain/sg_domain.dart';

/// Demo data matching the designs: 25 workers, Day and Night shifts, today's
/// marks at the gate, a month of history and four open exceptions.
///
/// Today is 24-10-2026 (a Saturday).
class DemoSeed {
  new({DateTime? today}) : today = today ?? DateTime(2026, 10, 24) {
    _build();
  }

  final DateTime today;

  static const dayShift = Shift(
    id: 'shift-day',
    name: 'Day',
    startMinute: 6 * 60,
    endMinute: 14 * 60,
  );
  static const nightShift = Shift(
    id: 'shift-night',
    name: 'Night',
    startMinute: 22 * 60,
    endMinute: 6 * 60,
  );

  /// Dev-only PINs, shown in the debug panel.
  static const ownerPin = '123456';
  static const adminPin = '234567';
  static const operatorPin = '345678';

  static const departments = [
    'Cutting',
    'Stitching',
    'Weaving',
    'Dyeing',
    'Packing',
  ];
  static const contractors = ['Shree Manpower', 'Om Labour Supply'];

  final workers = <Worker>[];
  final events = <AttendanceEvent>[];
  final exceptions = <ExceptionRecord>[];

  /// Workers marked IN at the gate this morning, with the minute they came.
  static const _todayIn = <int, String>{
    101: '05:46',
    102: '05:44',
    103: '05:48',
    104: '05:50',
    105: '05:45',
    107: '05:47',
    108: '05:43',
    109: '05:51',
    111: '05:42',
    113: '05:40',
    115: '05:49',
    116: '05:41',
    117: '05:39',
    118: '05:51',
    120: '05:38',
    // Night shift: arrived before midnight. The fake counts calendar days,
    // so the mark is stored just after midnight.
    121: '00:02',
    123: '05:37',
  };

  // code, name, department, designation, shift, language
  static const _rows = <(int, String, String, String, String, AppLanguage)>[
    (101, 'Deepak Yadav', 'Cutting', 'Cutter', 'day', AppLanguage.hi),
    (102, 'Sanjay Gupta', 'Weaving', 'Weaver', 'day', AppLanguage.hi),
    (103, 'Fatima Shaikh', 'Packing', 'Packer', 'day', AppLanguage.hi),
    (104, 'Gurpreet Singh', 'Cutting', 'Cutter', 'day', AppLanguage.pa),
    (
      105,
      'Rekha Jadhav',
      'Stitching',
      'Machine operator',
      'day',
      AppLanguage.mr,
    ),
    (
      106,
      'Kavita Patil',
      'Stitching',
      'Machine operator',
      'day',
      AppLanguage.mr,
    ),
    (107, 'Arjun Nair', 'Weaving', 'Weaver', 'day', AppLanguage.en),
    (108, 'Imran Ansari', 'Dyeing', 'Dyer', 'day', AppLanguage.hi),
    (109, 'Mohd. Irfan', 'Dyeing', 'Dyer', 'day', AppLanguage.hi),
    (110, 'Meena Kumari', 'Packing', 'Packer', 'day', AppLanguage.hi),
    (111, 'Anil Chauhan', 'Weaving', 'Weaver', 'day', AppLanguage.hi),
    (112, 'Ramesh Kumar', 'Weaving', 'Weaver', 'day', AppLanguage.hi),
    (113, 'Joseph Dsouza', 'Packing', 'Supervisor', 'day', AppLanguage.en),
    (
      114,
      'Pooja Verma',
      'Stitching',
      'Machine operator',
      'day',
      AppLanguage.hi,
    ),
    (115, 'Lakshmi M.', 'Stitching', 'Machine operator', 'day', AppLanguage.ta),
    (116, 'Harish Patel', 'Cutting', 'Cutter', 'day', AppLanguage.gu),
    (
      117,
      'Bhavna Solanki',
      'Stitching',
      'Machine operator',
      'day',
      AppLanguage.gu,
    ),
    (118, 'Anita Sharma', 'Packing', 'Packer', 'day', AppLanguage.hi),
    (119, 'Suresh Rao', 'Cutting', 'Cutter', 'day', AppLanguage.en),
    (120, 'Nilesh Jain', 'Dyeing', 'Dyer', 'day', AppLanguage.hi),
    (121, 'Prakash Kale', 'Dyeing', 'Dyer', 'night', AppLanguage.mr),
    (122, 'Vijay Thakur', 'Dyeing', 'Dyer', 'day', AppLanguage.hi),
    (123, 'Mahesh Tiwari', 'Weaving', 'Weaver', 'day', AppLanguage.hi),
    (124, 'Salma Khatoon', 'Packing', 'Packer', 'day', AppLanguage.hi),
    (
      125,
      'Sunita Devi',
      'Stitching',
      'Machine operator',
      'day',
      AppLanguage.hi,
    ),
  ];

  static String workerId(int code) => 'w-0$code';

  DateTime _at(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  void _build() {
    for (final (code, name, dept, designation, shift, lang) in _rows) {
      workers.add(
        Worker(
          id: workerId(code),
          code: 'W-0$code',
          name: name,
          dateOfBirth: DateTime(1985 + code % 15, 1 + code % 12, 1 + code % 27),
          department: dept,
          designation: designation,
          shiftId: shift == 'day' ? dayShift.id : nightShift.id,
          language: lang,
          contractor: code % 7 == 0 ? contractors.first : null,
          faceStatus: code == 125 ? FaceStatus.needsFace : FaceStatus.enrolled,
          onLeave: code == 124,
        ),
      );
    }

    var n = 0;
    String nextId() => 'ev-seed-${n++}';

    // Month history (1st to yesterday).
    for (final w in workers) {
      final code = int.parse(w.code.substring(2));
      if (w.faceStatus != FaceStatus.enrolled) continue;
      final night = w.shiftId == nightShift.id;
      for (var d = 1; d < today.day; d++) {
        final day = DateTime(today.year, today.month, d);
        if (day.weekday == DateTime.sunday) continue;
        final rng = Random(code * 131 + d);
        if (rng.nextInt(100) < 8) continue; // absent
        final late = !night && rng.nextInt(100) < 10;
        // Night shift marks are stored on the calendar day they fall on: IN
        // just after midnight, OUT at 06:00 (the fake has no shift dates).
        final inTime = night
            ? _at(day, '00:0${rng.nextInt(9)}')
            : late
            ? _at(
                day,
                '06:${(12 + rng.nextInt(30)).toString().padLeft(2, '0')}',
              )
            : _at(
                day,
                '05:${(30 + rng.nextInt(28)).toString().padLeft(2, '0')}',
              );
        events.add(
          AttendanceEvent(
            id: nextId(),
            workerId: w.id,
            at: inTime,
            direction: Direction.checkIn,
            method: MarkMethod.face,
            onTime: !late,
          ),
        );
        final overtime = !night && rng.nextInt(100) < 25;
        final outTime = night
            ? _at(day, '06:0${rng.nextInt(6)}')
            : _at(
                day,
                overtime
                    ? '15:${rng.nextInt(50).toString().padLeft(2, '0')}'
                    : '14:${rng.nextInt(25).toString().padLeft(2, '0')}',
              );
        final yesterday = DateTime(today.year, today.month, today.day - 1);
        final skipOut = code == 109 && day == yesterday;
        if (!skipOut) {
          events.add(
            AttendanceEvent(
              id: nextId(),
              workerId: w.id,
              at: outTime,
              direction: Direction.checkOut,
              method: MarkMethod.face,
            ),
          );
        }
      }
    }

    // Today's marks at the gate.
    for (final entry in _todayIn.entries) {
      events.add(
        AttendanceEvent(
          id: nextId(),
          workerId: workerId(entry.key),
          at: _at(today, entry.value),
          direction: Direction.checkIn,
          method: MarkMethod.face,
        ),
      );
    }

    final yesterday = DateTime(today.year, today.month, today.day - 1);
    exceptions.addAll([
      ExceptionRecord(
        id: 'ex-1',
        kind: ExceptionKind.missingOut,
        at: _at(yesterday, '14:00'),
        workerId: workerId(109),
        inAt: _at(yesterday, '05:51'),
      ),
      ExceptionRecord(
        id: 'ex-2',
        kind: ExceptionKind.manual,
        at: _at(yesterday, '05:52'),
        workerId: workerId(106),
        actor: 'G-02',
        reason: ManualReason.cameraIssue,
      ),
      ExceptionRecord(
        id: 'ex-3',
        kind: ExceptionKind.manual,
        at: _at(yesterday, '05:58'),
        workerId: workerId(119),
        actor: 'G-02',
        reason: ManualReason.maskHelmet,
      ),
      ExceptionRecord(
        id: 'ex-4',
        kind: ExceptionKind.clock,
        at: _at(today, '02:10'),
        minutes: 14,
        count: 3,
      ),
    ]);
  }
}
