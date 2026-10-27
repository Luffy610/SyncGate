/// Indian formats (ADR-0016): dates as DD-MM-YYYY, 12-hour time with AM/PM by
/// default (24-hour as a setting), Indian digit grouping, Western digits.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// `24-10-2026`.
String formatDate(DateTime d) => '${_two(d.day)}-${_two(d.month)}-${d.year}';

/// `24-10`, for compact lists.
String formatDayMonth(DateTime d) => '${_two(d.day)}-${_two(d.month)}';

/// `24-10-2026, 7:40 PM`.
String formatDateTime(DateTime d, {bool use24h = false}) =>
    '${formatDate(d)}, ${formatTime(d, use24h: use24h)}';

/// `HH:mm`, 24-hour. Used in lists and on the gate footer.
String formatHm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// `7:40 PM` or `19:40`. With [padHour] the 12-hour form is `07:40 PM`.
String formatTime(DateTime d, {bool use24h = false, bool padHour = false}) {
  if (use24h) return formatHm(d);
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final h = padHour ? _two(hour) : '$hour';
  return '$h:${_two(d.minute)} ${meridiem(d)}';
}

/// `AM` or `PM`.
String meridiem(DateTime d) => d.hour < 12 ? 'AM' : 'PM';

/// `06:00` from minutes since midnight.
String formatMinuteOfDay(int minute) {
  final m = minute % (24 * 60);
  return '${_two(m ~/ 60)}:${_two(m % 60)}';
}

/// `06:00–14:00`.
String formatShiftWindow(int startMinute, int endMinute) =>
    '${formatMinuteOfDay(startMinute)}–${formatMinuteOfDay(endMinute)}';

const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysHi = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];
const _monthsEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _monthsHi = [
  'जन॰',
  'फ़र॰',
  'मार्च',
  'अप्रै॰',
  'मई',
  'जून',
  'जुल॰',
  'अग॰',
  'सित॰',
  'अक्तू॰',
  'नव॰',
  'दिस॰',
];

String weekdayShort(DateTime d, String languageCode) =>
    (languageCode == 'hi' ? _weekdaysHi : _weekdaysEn)[d.weekday - 1];

/// `Sat, 24-10-2026`.
String formatDateWithWeekday(DateTime d, String languageCode) =>
    '${weekdayShort(d, languageCode)}, ${formatDate(d)}';

/// `Oct 2026`.
String formatMonthYear(DateTime d, String languageCode) =>
    '${(languageCode == 'hi' ? _monthsHi : _monthsEn)[d.month - 1]} ${d.year}';

/// Indian digit grouping: `1,23,456`. Western digits.
String formatNumber(num value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final negative = fixed.startsWith('-');
  final parts = (negative ? fixed.substring(1) : fixed).split('.');
  final digits = parts.first;
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }
  final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';
  return '${negative ? '-' : ''}$grouped$decimalPart';
}
