const dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

final _letters = RegExp(
  "'[^']*'|EEEE|EEE|MMMM|MMM|MM|M|dd|d|yyyy|yy|HH|H|hh|h|mm|ss|a",
);

/// [time] written to [pattern], in which `HH` `H` are the hour of 24, `hh`
/// `h` the hour of 12, `mm` minutes, `ss` seconds, `a` am or pm, `EEEE`
/// `EEE` the day's name, `d` `dd` the day, `MMMM` `MMM` the month's name,
/// `M` `MM` its number and `yyyy` `yy` the year. Anything else stands as it
/// is, as do words between single quotes.
String formatDateTime(DateTime time, String pattern) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return pattern.replaceAllMapped(_letters, (match) {
    final letters = match[0]!;
    return switch (letters) {
      'EEEE' => dayNames[time.weekday - 1],
      'EEE' => dayNames[time.weekday - 1].substring(0, 3),
      'MMMM' => monthNames[time.month - 1],
      'MMM' => monthNames[time.month - 1].substring(0, 3),
      'MM' => two(time.month),
      'M' => '${time.month}',
      'dd' => two(time.day),
      'd' => '${time.day}',
      'yyyy' => '${time.year}',
      'yy' => two(time.year % 100),
      'HH' => two(time.hour),
      'H' => '${time.hour}',
      'hh' => two(hour12),
      'h' => '$hour12',
      'mm' => two(time.minute),
      'ss' => two(time.second),
      'a' => time.hour < 12 ? 'am' : 'pm',
      _ => letters.substring(1, letters.length - 1),
    };
  });
}
