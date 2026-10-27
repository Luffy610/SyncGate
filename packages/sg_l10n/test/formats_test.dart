import 'package:flutter_test/flutter_test.dart';
import 'package:sg_l10n/sg_l10n.dart';

void main() {
  final d = DateTime(2026, 10, 24, 19, 40);

  test('dates are DD-MM-YYYY', () {
    expect(formatDate(d), '24-10-2026');
    expect(formatDate(DateTime(2026, 3, 5)), '05-03-2026');
    expect(formatDayMonth(d), '24-10');
  });

  test('12-hour time by default, 24-hour on request', () {
    expect(formatTime(d), '7:40 PM');
    expect(formatTime(d, use24h: true), '19:40');
    expect(
      formatTime(DateTime(2026, 10, 24, 5, 52), padHour: true),
      '05:52 AM',
    );
    expect(formatTime(DateTime(2026, 10, 24, 0, 5)), '12:05 AM');
    expect(formatTime(DateTime(2026, 10, 24, 12, 5)), '12:05 PM');
  });

  test('shift windows', () {
    expect(formatShiftWindow(360, 840), '06:00–14:00');
    expect(formatShiftWindow(1320, 360), '22:00–06:00');
  });

  test('weekday and month names follow the language', () {
    expect(formatDateWithWeekday(d, 'en'), 'Sat, 24-10-2026');
    expect(formatDateWithWeekday(d, 'hi'), 'शनि, 24-10-2026');
    expect(formatMonthYear(d, 'en'), 'Oct 2026');
  });

  test('Indian digit grouping with Western digits', () {
    expect(formatNumber(999), '999');
    expect(formatNumber(1234), '1,234');
    expect(formatNumber(123456), '1,23,456');
    expect(formatNumber(12345678), '1,23,45,678');
    expect(formatNumber(6.5, decimals: 1), '6.5');
    expect(formatNumber(-1234567), '-12,34,567');
  });
}
