import 'package:sg_domain/sg_domain.dart';
import 'package:test/test.dart';

Worker _worker(
  String id, {
  String shift = 's1',
  FaceStatus face = FaceStatus.enrolled,
  bool onLeave = false,
  bool active = true,
}) => Worker(
  id: id,
  code: 'W-$id',
  name: 'Worker $id',
  dateOfBirth: DateTime(1990),
  department: 'Cutting',
  designation: 'Cutter',
  shiftId: shift,
  faceStatus: face,
  onLeave: onLeave,
  active: active,
);

AttendanceEvent _event(
  String worker,
  Direction direction,
  int hour,
  int minute, {
  bool onTime = true,
  MarkMethod method = MarkMethod.face,
}) => AttendanceEvent(
  id: '$worker-$hour$minute',
  workerId: worker,
  at: DateTime(2026, 10, 24, hour, minute),
  direction: direction,
  method: method,
  onTime: onTime,
);

void main() {
  const day = Shift(id: 's1', name: 'Day', startMinute: 360, endMinute: 840);
  const night = Shift(
    id: 's2',
    name: 'Night',
    startMinute: 1320,
    endMinute: 360,
  );

  group('isExpected', () {
    test('needs an enrolled, active worker who is not on leave', () {
      expect(TodayCalculator.isExpected(_worker('1')), isTrue);
      expect(
        TodayCalculator.isExpected(_worker('2', face: FaceStatus.needsFace)),
        isFalse,
      );
      expect(TodayCalculator.isExpected(_worker('3', onLeave: true)), isFalse);
      expect(TodayCalculator.isExpected(_worker('4', active: false)), isFalse);
    });
  });

  group('statusOf', () {
    test('needs face wins over everything', () {
      final w = _worker('1', face: FaceStatus.needsFace);
      expect(TodayCalculator.statusOf(w, const []), isA<StatusNeedsFace>());
    });

    test('IN, then OUT, by the last mark', () {
      final w = _worker('1');
      final ins = [_event('1', Direction.checkIn, 5, 50)];
      expect(TodayCalculator.statusOf(w, ins), isA<StatusIn>());
      final out = [...ins, _event('1', Direction.checkOut, 14, 5)];
      expect(TodayCalculator.statusOf(w, out), isA<StatusOut>());
    });

    test('not in, or on leave', () {
      expect(
        TodayCalculator.statusOf(_worker('1'), const []),
        isA<StatusNotIn>(),
      );
      expect(
        TodayCalculator.statusOf(_worker('1', onLeave: true), const []),
        isA<StatusOnLeave>(),
      );
    });
  });

  group('gateProgress', () {
    test('counts expected workers of the shift who marked IN', () {
      final workers = [
        _worker('1'),
        _worker('2'),
        _worker('3'),
        _worker('4', shift: 's2'),
        _worker('5', onLeave: true),
      ];
      final events = [
        _event('1', Direction.checkIn, 5, 50),
        _event('4', Direction.checkIn, 0, 5),
      ];
      final p = TodayCalculator.gateProgress(
        workers: workers,
        events: events,
        shiftId: 's1',
      );
      expect(p, (marked: 1, expected: 3));
    });
  });

  group('summary', () {
    final workers = [
      _worker('1'),
      _worker('2'),
      _worker('3'),
      _worker('4'),
      _worker('5', onLeave: true),
    ];
    final events = [
      _event('1', Direction.checkIn, 5, 50),
      _event('2', Direction.checkIn, 6, 30, onTime: false),
      _event('3', Direction.checkIn, 5, 55),
      _event('3', Direction.checkOut, 13, 10),
    ];

    TodaySummary at(int hour, int minute) => TodayCalculator.summary(
      workers: workers,
      events: events,
      shifts: [day, night],
      now: DateTime(2026, 10, 24, hour, minute),
      shiftId: 's1',
    );

    test('nobody is absent before the grace time ends', () {
      final s = at(6, 5);
      expect(s.expected, 4);
      expect(s.present, 3);
      expect(s.absent, 0);
      expect(s.onLeave, 1);
    });

    test('after the grace time the missing worker is absent', () {
      final s = at(10, 42);
      expect(s.absent, 1);
      expect(s.late, 1);
      expect(s.lateAfterLabel, '06:10');
    });

    test('on premises and went OUT', () {
      final s = at(14, 0);
      expect(s.onPremises, 2);
      expect(s.wentOut, 1);
    });
  });

  group('manualCandidates', () {
    final workers = [_worker('1'), _worker('2'), _worker('3', shift: 's2')];

    test('lists unmarked workers of the running shift, by name', () {
      final list = TodayCalculator.manualCandidates(
        workers: workers,
        events: [_event('1', Direction.checkIn, 5, 50)],
        shifts: [day, night],
        now: DateTime(2026, 10, 24, 5, 52),
        shiftId: 's1',
      );
      expect(list.map((c) => c.worker.id), ['2']);
      expect(list.single.direction, Direction.checkIn);
    });

    test('near the end of the shift, IN workers can be marked OUT', () {
      final list = TodayCalculator.manualCandidates(
        workers: workers,
        events: [_event('1', Direction.checkIn, 5, 50)],
        shifts: [day, night],
        now: DateTime(2026, 10, 24, 13, 30),
        shiftId: 's1',
      );
      expect(
        list.map((c) => (c.worker.id, c.direction)),
        containsAll([('1', Direction.checkOut), ('2', Direction.checkIn)]),
      );
    });
  });

  test('manualEntryCount counts only manual marks of the worker', () {
    final events = [
      _event('1', Direction.checkIn, 5, 50, method: MarkMethod.manual),
      _event('1', Direction.checkOut, 6, 50, method: MarkMethod.manual),
      _event('1', Direction.checkIn, 7, 50),
      _event('2', Direction.checkIn, 5, 50, method: MarkMethod.manual),
    ];
    expect(TodayCalculator.manualEntryCount(events, '1'), 2);
  });
}
