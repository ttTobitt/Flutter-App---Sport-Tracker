/// Formatierung für deutsche Anzeige (Komma statt Punkt, deutsche Wochentage).
/// Bewusst ohne das `intl`-Paket, weil wir nur diese paar Formate brauchen.
library;

const _weekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// 7.234 → "7,2"
String formatNumber(double value, {int decimals = 1}) =>
    value.toStringAsFixed(decimals).replaceAll('.', ',');

/// "Dienstag, 29.09."
String formatDayTitle(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_two(d.day)}.${_two(d.month)}.';

/// "Di 29.09."
String formatDayShort(DateTime d) =>
    '${_weekdays[d.weekday - 1].substring(0, 2)} ${_two(d.day)}.${_two(d.month)}.';

/// "18:30"
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// 92 min
int minutesOf(Duration d) => d.inSeconds ~/ 60;
