import 'dart:math';
import 'dart:ui';

import '../models/pitch.dart';
import '../models/sensor_data.dart';
import '../models/session.dart';

/// Erzeugt eine erfundene, aber realistische Einheit, so als wäre sie gerade
/// vom Tracker übertragen worden. Damit lässt sich die App ohne Hardware
/// entwickeln.
///
/// Der Spieler läuft als rechter Mittelfeldspieler von Ziel zu Ziel, mal
/// gehend, mal trabend, mal sprintend. Aufgezeichnet wird mit 5 Hz wie am
/// echten Tracker.
class MockSessionGenerator {
  static const _hz = 5;

  // Beispielplatz, Koordinaten frei gewählt
  static const pitch = Pitch(centerLat: 48.1351, centerLon: 11.5820);

  // (min km/h, max km/h, Wahrscheinlichkeit)
  static const _modes = [
    (0.0, 2.0, 0.25), // stehen
    (4.0, 6.0, 0.32), // gehen
    (8.0, 12.0, 0.27), // traben
    (15.0, 18.0, 0.13), // laufen
    (22.0, 29.0, 0.03), // sprinten
  ];

  static Session generate({
    required int id,
    required DateTime start,
    Duration duration = const Duration(minutes: 92),
  }) {
    final rnd = Random(id);
    final points = <SensorData>[];
    final totalSteps = duration.inSeconds * _hz;

    // Stammposition rechtes Mittelfeld. Angriff nach rechts (x = 105),
    // y groß = rechte Seitenlinie aus Sicht des Spielers.
    const home = Offset(62, 54);
    var pos = home;
    var target = pos;
    var speedKmh = 0.0;
    // Wo der Ball gerade ist, schiebt die ganze Mannschaft vor oder zurück
    var teamShift = 0.0;

    for (var step = 0; step < totalSteps; step++) {
      // Ziel erreicht → neues Ziel und neues Tempo wählen
      if ((target - pos).distance < 1.0 || speedKmh < 3 && rnd.nextDouble() < 0.02) {
        final mode = _pickMode(rnd);
        speedKmh = mode.$1 + rnd.nextDouble() * (mode.$2 - mode.$1);
        if (rnd.nextDouble() < 0.15) teamShift = -22 + rnd.nextDouble() * 45;

        // Ziel streut um die Stammposition (Normalverteilung). Sprints gehen
        // meist nach vorne (Konter, Flanke) oder zurück (Rückwärtslaufen).
        var dx = teamShift + _gauss(rnd) * 8;
        if (speedKmh > 20) dx += (rnd.nextBool() ? 1 : -1) * (15 + rnd.nextDouble() * 15);
        target = Offset(
          (home.dx + dx).clamp(3, 102),
          (home.dy + _gauss(rnd) * 6).clamp(3, 66),
        );
      }

      // Kleines Rauschen auf die Geschwindigkeit wie bei echtem GPS
      final noisy = max(0.0, speedKmh + (rnd.nextDouble() - 0.5) * 0.8);
      final stepMeters = noisy / 3.6 / _hz;
      final dir = target - pos;
      if (dir.distance > 0) {
        pos += dir / dir.distance * min(stepMeters, dir.distance);
      }

      final (lat, lon) = pitch.toGps(pos);
      points.add(SensorData(
        timestamp: start.add(Duration(milliseconds: step * 1000 ~/ _hz)),
        latitude: lat,
        longitude: lon,
        speedKmh: noisy,
      ));
    }

    return Session(id: id, points: points, pitch: pitch);
  }

  /// Normalverteilte Zufallszahl (Mittelwert 0, Standardabweichung 1),
  /// Box-Muller-Verfahren
  static double _gauss(Random rnd) =>
      sqrt(-2 * log(1 - rnd.nextDouble())) * cos(2 * pi * rnd.nextDouble());

  static (double, double, double) _pickMode(Random rnd) {
    var r = rnd.nextDouble();
    for (final mode in _modes) {
      if (r < mode.$3) return mode;
      r -= mode.$3;
    }
    return _modes.first;
  }
}
