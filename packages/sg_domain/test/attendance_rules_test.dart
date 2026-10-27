import 'package:sg_domain/sg_domain.dart';
import 'package:test/test.dart';

AttendanceEvent _event(Direction d, DateTime at) => AttendanceEvent(
  id: 'e',
  workerId: 'w',
  at: at,
  direction: d,
  method: MarkMethod.face,
);

void main() {
  const day = Shift(
    id: 's1',
    name: 'Day',
    startMinute: 6 * 60,
    endMinute: 14 * 60,
  );
  const night = Shift(
    id: 's2',
    name: 'Night',
    startMinute: 22 * 60,
    endMinute: 6 * 60,
  );
  final now = DateTime(2026, 10, 24, 5, 52);

  group('nextDirection', () {
    test('first mark of the day is IN', () {
      expect(AttendanceRules.nextDirection(null, now), Direction.checkIn);
    });

    test('an IN today is followed by OUT, an OUT by IN', () {
      final inAt = _event(Direction.checkIn, DateTime(2026, 10, 24, 5, 40));
      final outAt = _event(Direction.checkOut, DateTime(2026, 10, 24, 5, 41));
      expect(AttendanceRules.nextDirection(inAt, now), Direction.checkOut);
      expect(AttendanceRules.nextDirection(outAt, now), Direction.checkIn);
    });

    test('a mark from yesterday starts a new day with IN', () {
      final old = _event(Direction.checkIn, DateTime(2026, 10, 23, 5, 50));
      expect(AttendanceRules.nextDirection(old, now), Direction.checkIn);
    });
  });

  group('cooldown', () {
    final last = _event(Direction.checkIn, DateTime(2026, 10, 24, 5, 51));

    test('marks within two minutes are ignored', () {
      expect(AttendanceRules.inCooldown(last, now), isTrue);
    });

    test('marks after two minutes are accepted', () {
      expect(
        AttendanceRules.inCooldown(last, DateTime(2026, 10, 24, 5, 54)),
        isFalse,
      );
    });

    test('no previous mark means no cooldown', () {
      expect(AttendanceRules.inCooldown(null, now), isFalse);
    });
  });

  group('isOnTime', () {
    test('up to start plus grace', () {
      expect(
        AttendanceRules.isOnTime(day, DateTime(2026, 10, 24, 6, 10)),
        true,
      );
      expect(
        AttendanceRules.isOnTime(day, DateTime(2026, 10, 24, 6, 11)),
        false,
      );
    });

    test('night shift after midnight is on time', () {
      expect(AttendanceRules.isOnTime(night, DateTime(2026, 10, 25, 1)), true);
    });
  });

  group('shift window', () {
    test('day shift runs from an hour before start to the end', () {
      expect(day.isRunningAt(DateTime(2026, 10, 24, 5, 30)), isTrue);
      expect(day.isRunningAt(DateTime(2026, 10, 24, 4, 30)), isFalse);
      expect(day.isRunningAt(DateTime(2026, 10, 24, 14)), isFalse);
    });

    test('night shift crosses midnight', () {
      expect(night.crossesMidnight, isTrue);
      expect(night.isRunningAt(DateTime(2026, 10, 24, 23)), isTrue);
      expect(night.isRunningAt(DateTime(2026, 10, 25, 3)), isTrue);
      expect(night.isRunningAt(DateTime(2026, 10, 25, 12)), isFalse);
    });
  });

  group('age', () {
    test('counts whole years', () {
      expect(AttendanceRules.ageOn(DateTime(1998, 3, 12), now), 28);
      expect(AttendanceRules.ageOn(DateTime(1998, 12), now), 27);
    });

    test('18th birthday is the cut-off', () {
      expect(AttendanceRules.isAdult(DateTime(2008, 10, 24), now), isTrue);
      expect(AttendanceRules.isAdult(DateTime(2008, 10, 25), now), isFalse);
    });
  });

  group('parseDate', () {
    test('accepts DD-MM-YYYY', () {
      expect(AttendanceRules.parseDate('12-03-1998'), DateTime(1998, 3, 12));
    });

    test('rejects impossible and badly formatted dates', () {
      expect(AttendanceRules.parseDate('31-02-1998'), isNull);
      expect(AttendanceRules.parseDate('1998-03-12'), isNull);
      expect(AttendanceRules.parseDate('12-03-98'), isNull);
    });
  });

  group('PinPolicy', () {
    test('no lockout for the first four failures', () {
      for (var i = 0; i < 5; i++) {
        expect(PinPolicy.lockoutAfter(i), Duration.zero);
      }
    });

    test('back-off doubles and caps at 15 minutes', () {
      expect(PinPolicy.lockoutAfter(5), const Duration(seconds: 30));
      expect(PinPolicy.lockoutAfter(6), const Duration(minutes: 1));
      expect(PinPolicy.lockoutAfter(7), const Duration(minutes: 2));
      expect(PinPolicy.lockoutAfter(20), const Duration(minutes: 15));
    });
  });

  group('roles', () {
    test('gate operator cannot see reports or enrol', () {
      expect(Role.gateOperator.can(Capability.reportsAndExports), isFalse);
      expect(Role.gateOperator.can(Capability.enrolWorkers), isFalse);
      expect(Role.gateOperator.can(Capability.manualEntry), isTrue);
    });

    test('admin cannot back up or manage users', () {
      expect(Role.admin.can(Capability.backupRestore), isFalse);
      expect(Role.admin.can(Capability.licenceAndUsers), isFalse);
      expect(Role.admin.can(Capability.corrections), isTrue);
    });

    test('owner can do everything', () {
      for (final c in Capability.values) {
        expect(Role.owner.can(c), isTrue, reason: c.name);
      }
    });
  });
}
