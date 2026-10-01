import '../models/sensor_data.dart';

/// Eine erkannte Halbzeitpause. Die Indizes zeigen in die Punkteliste der
/// Einheit, [endIndex] ist der letzte Punkt der Pause.
///
/// Gab es in der Pause gar keine Punkte (kein GPS in der Kabine), ist
/// endIndex = startIndex − 1. Die Pause ist dann leer, [startIndex] ist der
/// erste Punkt der 2. Halbzeit.
class Halftime {
  final int startIndex;
  final int endIndex;
  final Duration start; // seit Beginn der Einheit
  final Duration end;

  const Halftime(this.startIndex, this.endIndex, this.start, this.end);

  bool contains(int index) => index >= startIndex && index <= endIndex;
}

/// Sucht die Halbzeitpause in einer Einheit.
///
/// Die Einheit wird in Minuten eingeteilt. Eine Minute zählt als Pause, wenn
/// - der Spieler sich kaum bewegt (Ø unter [pauseSpeedKmh]) oder
/// - kaum Messpunkte da sind (z. B. in der Kabine ohne GPS-Empfang; der
///   Tracker speichert nur Punkte mit gültigem GPS-Fix).
///
/// Die Halbzeit ist die längste zusammenhängende Pause von [minLength] bis
/// [maxLength], die zwischen 25 % und 65 % der Einheit beginnt. Ohne solche
/// Pause gibt es kein Ergebnis (dann ist es vermutlich ein Training).
Halftime? detectHalftime(
  List<SensorData> points, {
  double pauseSpeedKmh = 3,
  Duration minLength = const Duration(minutes: 8),
  Duration maxLength = const Duration(minutes: 30),
  int hz = 5,
}) {
  if (points.length < 2) return null;
  final start = points.first.timestamp;
  final totalMinutes = points.last.timestamp.difference(start).inMinutes + 1;

  // Punkte pro Minute zählen und Geschwindigkeit aufsummieren
  final counts = List.filled(totalMinutes, 0);
  final speedSums = List.filled(totalMinutes, 0.0);
  for (final p in points) {
    final m = p.timestamp.difference(start).inMinutes;
    counts[m]++;
    speedSums[m] += p.speedKmh;
  }
  final expectedPerMinute = 60 * hz;
  bool isPause(int m) =>
      counts[m] < expectedPerMinute * 0.3 || speedSums[m] / counts[m] < pauseSpeedKmh;

  // Längste Pause suchen, die im erlaubten Bereich beginnt
  int? bestStart;
  var bestLength = 0;
  var m = 0;
  while (m < totalMinutes) {
    if (!isPause(m)) {
      m++;
      continue;
    }
    final runStart = m;
    while (m < totalMinutes && isPause(m)) {
      m++;
    }
    final length = m - runStart;
    final startShare = runStart / totalMinutes;
    if (startShare >= 0.25 &&
        startShare <= 0.65 &&
        length >= minLength.inMinutes &&
        length <= maxLength.inMinutes &&
        length > bestLength) {
      bestStart = runStart;
      bestLength = length;
    }
  }
  if (bestStart == null) return null;

  // Minuten → Punkt-Indizes
  final from = Duration(minutes: bestStart);
  final to = Duration(minutes: bestStart + bestLength);
  final startIndex = points.indexWhere((p) => p.timestamp.difference(start) >= from);
  final afterIndex = points.indexWhere((p) => p.timestamp.difference(start) >= to);
  if (startIndex == -1) return null;
  final endIndex = (afterIndex == -1 ? points.length : afterIndex) - 1;

  return Halftime(startIndex, endIndex, from, to);
}
