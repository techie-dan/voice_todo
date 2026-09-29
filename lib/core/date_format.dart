/// Date and time formatting, hand-rolled.
///
/// The app needs four shapes of label and nothing else, so it does not take on
/// `intl` (and the locale data that comes with it). If real localisation is
/// ever needed, this is the file to replace.
library;

const List<String> _weekdayNames = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _monthNames = <String>[
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

String _two(int value) => value.toString().padLeft(2, '0');

/// 24-hour `HH:mm`.
String formatTime(DateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}';

/// Whole-day difference between two instants, immune to DST shifts because it
/// compares calendar dates in UTC rather than elapsed local time.
int _dayDelta(DateTime from, DateTime to) {
  final DateTime a = DateTime.utc(from.year, from.month, from.day);
  final DateTime b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Whether two instants fall on the same calendar day, in local time.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// `Mon 12 May`, or `12 May 2027` when the year differs from [now].
String formatShortDate(DateTime value, {DateTime? now}) {
  final DateTime clock = now ?? DateTime.now();
  final String day =
      '${_weekdayNames[value.weekday - 1]} ${value.day} ${_monthNames[value.month - 1]}';
  return value.year == clock.year ? day : '$day ${value.year}';
}

/// A due-date label: `Today 17:00`, `Tomorrow 09:00`, `Yesterday 08:00`,
/// `Thu 15:30` within the week, otherwise `Mon 12 May 09:00`.
String formatDueLabel(DateTime value, {DateTime? now}) {
  final DateTime clock = now ?? DateTime.now();
  final int delta = _dayDelta(clock, value);
  final String time = formatTime(value);
  return switch (delta) {
    0 => 'Today $time',
    1 => 'Tomorrow $time',
    -1 => 'Yesterday $time',
    > 1 && < 7 => '${_weekdayNames[value.weekday - 1]} $time',
    _ => '${formatShortDate(value, now: clock)} $time',
  };
}

/// A coarse "how long ago" label for note timestamps.
String formatRelative(DateTime value, {DateTime? now}) {
  final DateTime clock = now ?? DateTime.now();
  final Duration elapsed = clock.difference(value);

  if (elapsed.inSeconds < 60) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24 && _dayDelta(value, clock) == 0) {
    return '${elapsed.inHours} h ago';
  }
  final int delta = _dayDelta(clock, value);
  if (delta == 1 || (delta == 0 && elapsed.inHours >= 24)) return 'Yesterday';
  return formatShortDate(value, now: clock);
}
