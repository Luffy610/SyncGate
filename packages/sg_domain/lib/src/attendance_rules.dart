import 'package:sg_domain/src/entities.dart';

/// Pure attendance rules shared by the gate and reports (frontend plan §6.1;
/// the full shift engine is epic E08).
abstract final class AttendanceRules {
  /// Repeat marks inside this window are ignored (FR-ATT-05).
  static const defaultCooldown = Duration(seconds: 120);

  /// Manual entries per worker per day before admin review (ADR-0004 §3).
  static const manualEntryLimitPerDay = 3;

  static const minimumAge = 18;

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// IN after the last OUT (or with no mark today); OUT after an IN.
  static Direction nextDirection(AttendanceEvent? last, DateTime now) {
    if (last == null || !isSameDay(last.at, now)) return Direction.checkIn;
    return last.direction == Direction.checkIn
        ? Direction.checkOut
        : Direction.checkIn;
  }

  /// True if [last] is recent enough that a new mark should be ignored.
  static bool inCooldown(
    AttendanceEvent? last,
    DateTime now, {
    Duration cooldown = defaultCooldown,
  }) {
    if (last == null) return false;
    final elapsed = now.difference(last.at);
    return !elapsed.isNegative && elapsed < cooldown;
  }

  /// An IN is on time up to the shift start plus grace.
  static bool isOnTime(Shift shift, DateTime at) {
    final minute = at.hour * 60 + at.minute;
    if (shift.crossesMidnight && minute < shift.endMinute) return true;
    return minute <= shift.startMinute + shift.graceMinutes;
  }

  /// Whole years between [birth] and [on].
  static int ageOn(DateTime birth, DateTime on) {
    var age = on.year - birth.year;
    final hadBirthday =
        on.month > birth.month ||
        (on.month == birth.month && on.day >= birth.day);
    if (!hadBirthday) age--;
    return age;
  }

  static bool isAdult(DateTime birth, DateTime on) =>
      ageOn(birth, on) >= minimumAge;

  /// Parses `DD-MM-YYYY`. Returns `null` for anything that isn't a real date.
  static DateTime? parseDate(String text) {
    final match = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(text.trim());
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}

/// Lockout schedule for wrong PINs: 5 tries, then exponential back-off up to
/// 15 minutes (ADR-0004 §2).
abstract final class PinPolicy {
  static const length = 6;
  static const freeAttempts = 5;
  static const maxLockout = Duration(minutes: 15);

  /// Lockout after [failures] consecutive wrong PINs.
  static Duration lockoutAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final steps = failures - freeAttempts;
    final seconds = 30 * (1 << steps.clamp(0, 10));
    final lock = Duration(seconds: seconds);
    return lock > maxLockout ? maxLockout : lock;
  }
}
