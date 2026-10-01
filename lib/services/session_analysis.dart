import 'dart:math';

import '../models/sensor_data.dart';

/// Ein erkannter Sprint. Die Indizes zeigen in die Punkteliste der Einheit.
class Sprint {
  final int startIndex;
  final int endIndex; // inklusive
  final int peakIndex; // schnellster Punkt
  final double maxSpeedKmh;

  const Sprint(this.startIndex, this.endIndex, this.peakIndex, this.maxSpeedKmh);
}

/// Eine Geschwindigkeitszone, z. B. „Traben 7–14 km/h“.
class SpeedZone {
  final String name;
  final double fromKmh;
  final double toKmh;
  const SpeedZone(this.name, this.fromKmh, this.toKmh);
}

/// Berechnet aus den Rohpunkten einer Einheit alle Kennzahlen.
///
/// Die Auswertung passiert bewusst in der App und nicht am Tracker,
/// siehe Vault-Notiz „Übertragung nach dem Training“.
class SessionAnalysis {
  /// Ab dieser Geschwindigkeit zählt ein Lauf als Sprint …
  static const sprintThresholdKmh = 20.0;

  /// … wenn er mindestens so lange dauert.
  static const sprintMinDuration = Duration(seconds: 1);

  static const zones = [
    SpeedZone('Gehen', 0, 7),
    SpeedZone('Traben', 7, 14),
    SpeedZone('Laufen', 14, 20),
    SpeedZone('Sprint', 20, double.infinity),
  ];

  final List<SensorData> points;

  late final double distanceKm = _distanceKm();
  late final double maxSpeedKmh =
      points.isEmpty ? 0 : points.map((p) => p.speedKmh).reduce(max);
  late final double avgSpeedKmh = _avgSpeedKmh();
  late final List<Sprint> sprints = _findSprints();

  /// Zeitanteil pro Zone (0 … 1), in derselben Reihenfolge wie [zones]
  late final List<double> zoneShares = _zoneShares();

  SessionAnalysis(this.points);

  double _distanceKm() {
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += haversineMeters(points[i - 1], points[i]);
    }
    return meters / 1000;
  }

  double _avgSpeedKmh() {
    if (points.length < 2) return 0;
    final hours = points.last.timestamp
            .difference(points.first.timestamp)
            .inMilliseconds /
        3600000;
    return hours == 0 ? 0 : distanceKm / hours;
  }

  /// Sucht zusammenhängende Abschnitte über [sprintThresholdKmh], die
  /// mindestens [sprintMinDuration] lang sind.
  List<Sprint> _findSprints() {
    final result = <Sprint>[];
    int? startIndex;

    for (var i = 0; i <= points.length; i++) {
      final fast = i < points.length && points[i].speedKmh >= sprintThresholdKmh;
      if (fast && startIndex == null) {
        startIndex = i;
      } else if (!fast && startIndex != null) {
        final start = points[startIndex].timestamp;
        final end = points[i - 1].timestamp;
        if (end.difference(start) >= sprintMinDuration) {
          var peak = startIndex;
          for (var j = startIndex; j < i; j++) {
            if (points[j].speedKmh > points[peak].speedKmh) peak = j;
          }
          result.add(Sprint(startIndex, i - 1, peak, points[peak].speedKmh));
        }
        startIndex = null;
      }
    }
    return result;
  }

  List<double> _zoneShares() {
    final counts = List.filled(zones.length, 0);
    for (final p in points) {
      final zone = zones.indexWhere((z) => p.speedKmh < z.toKmh);
      counts[zone]++;
    }
    final total = points.isEmpty ? 1 : points.length;
    return counts.map((c) => c / total).toList();
  }

  /// Abstand zweier GPS-Punkte in Metern (Haversine-Formel).
  static double haversineMeters(SensorData a, SensorData b) {
    const earthRadius = 6371000.0;
    double rad(double deg) => deg * pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(rad(a.latitude)) *
            cos(rad(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return 2 * earthRadius * asin(sqrt(h));
  }
}
