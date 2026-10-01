import 'dart:math';
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../models/pitch.dart';
import '../models/sensor_data.dart';
import '../models/session.dart';
import 'pitch_detection.dart';

/// Erzeugt eine erfundene, aber realistische Einheit, so als wäre sie gerade
/// vom Tracker übertragen worden. Damit lässt sich die App ohne Hardware
/// entwickeln.
///
/// Der Spieler läuft als rechter Mittelfeldspieler von Ziel zu Ziel, mal
/// gehend, mal trabend, mal sprintend. Aufgezeichnet wird mit 5 Hz wie am
/// echten Tracker.
class MockSessionGenerator {
  static const _hz = 5;

  /// Hauptplatz der Heinrich Hartner Sportanlage in Pressbaum, Umriss aus
  /// OpenStreetMap (Way 30581764, © OpenStreetMap-Mitwirkende, ODbL)
  static const hartnerPolygon = [
    LatLng(48.178011, 16.0675983),
    LatLng(48.1780708, 16.0689703),
    LatLng(48.1775356, 16.0690286),
    LatLng(48.177475, 16.0676506),
    LatLng(48.178011, 16.0675983),
  ];

  /// Kleiner Platz direkt daneben (Way 463661206). Wird in den Tests
  /// gebraucht: Die Erkennung darf ihn nicht mit dem Hauptplatz verwechseln.
  static const neighbourPolygon = [
    LatLng(48.1772743, 16.0689283),
    LatLng(48.1769096, 16.068972),
    LatLng(48.1769664, 16.0700375),
    LatLng(48.1773311, 16.0699938),
    LatLng(48.1772743, 16.0689283),
  ];

  static final Pitch pitch = pitchFromPolygon(hartnerPolygon)!;

  // (min km/h, max km/h, Wahrscheinlichkeit)
  static const _modes = [
    (0.0, 2.0, 0.25), // stehen
    (4.0, 6.0, 0.32), // gehen
    (8.0, 12.0, 0.27), // traben
    (15.0, 18.0, 0.13), // laufen
    (22.0, 29.0, 0.03), // sprinten
  ];

  /// Erzeugt eine Einheit. Bei [isMatch] zwei Halbzeiten à 45 min mit
  /// 15 min Pause am Spielfeldrand und Seitenwechsel, sonst ein Training
  /// über [duration] am Stück.
  static Session generate({
    required int id,
    required DateTime start,
    Duration duration = const Duration(minutes: 92),
    bool isMatch = false,
  }) {
    final rnd = Random(id);
    final points = <SensorData>[];
    var step = 0;

    // Stammposition rechtes Mittelfeld. Angriff nach rechts (x = Länge),
    // y groß = rechte Seitenlinie aus Sicht des Spielers.
    final home = Offset(pitch.length * 0.59, pitch.width * 0.8);
    var pos = home; // in „Mannschafts-Sicht“ (Angriff immer nach rechts)
    var target = pos;
    var speedKmh = 0.0;
    // Wo der Ball gerade ist, schiebt die ganze Mannschaft vor oder zurück
    var teamShift = 0.0;
    // Nach dem Seitenwechsel wird die echte Position um 180° gedreht
    var turned = false;

    Offset real(Offset p) =>
        turned ? Offset(pitch.length - p.dx, pitch.width - p.dy) : p;

    void record(Offset realPos, double kmh) {
      final (lat, lon) = pitch.toGps(realPos);
      points.add(SensorData(
        timestamp: start.add(Duration(milliseconds: step * 1000 ~/ _hz)),
        latitude: lat,
        longitude: lon,
        speedKmh: kmh,
      ));
      step++;
    }

    void move(double kmh) {
      final stepMeters = kmh / 3.6 / _hz;
      final dir = target - pos;
      if (dir.distance > 0) {
        pos += dir / dir.distance * min(stepMeters, dir.distance);
      }
    }

    void play(Duration length) {
      for (var i = 0; i < length.inSeconds * _hz; i++) {
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
            (home.dx + dx).clamp(3, pitch.length - 3),
            (home.dy + _gauss(rnd) * 6).clamp(3, pitch.width - 2),
          );
        }
        // Kleines Rauschen auf die Geschwindigkeit wie bei echtem GPS
        final noisy = max(0.0, speedKmh + (rnd.nextDouble() - 0.5) * 0.8);
        move(noisy);
        record(real(pos), noisy);
      }
    }

    /// Halbzeitpause: gemütlich zur Bank neben dem Feld gehen, dort stehen.
    void halftimeBreak(Duration length) {
      var realPos = real(pos);
      final bench = Offset(pitch.length / 2, pitch.width + 6);
      for (var i = 0; i < length.inSeconds * _hz; i++) {
        final dir = bench - realPos;
        final kmh = dir.distance > 1 ? 4.0 : rnd.nextDouble() * 0.8;
        if (dir.distance > 1) realPos += dir / dir.distance * (kmh / 3.6 / _hz);
        record(realPos, kmh);
      }
      // Zurück aufs Feld, jetzt mit getauschten Seiten
      turned = true;
      pos = home;
      target = home;
    }

    if (isMatch) {
      play(const Duration(minutes: 45));
      halftimeBreak(const Duration(minutes: 15));
      play(const Duration(minutes: 45));
    } else {
      play(duration);
    }

    // Ohne Platz und als Training zurückgeben, wie eine frisch übertragene
    // Einheit. Platz und Typ muss die App selbst erkennen.
    return Session(id: id, points: points);
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
