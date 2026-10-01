import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/pitch.dart';
import '../models/sensor_data.dart';

/// Geometrie für die Platz-Erkennung, ohne Internet und gut testbar.
/// Das Laden der Plätze aus OpenStreetMap macht `pitch_service.dart`.

/// Macht aus dem Umriss eines Platzes (Eckpunkte aus OpenStreetMap) ein
/// [Pitch] mit Mitte, Ausrichtung, Länge und Breite.
///
/// OSM-Umrisse sind nicht immer saubere Rechtecke (manchmal mehr Ecken,
/// leicht schief). Darum wird das kleinste Rechteck gesucht, das den Umriss
/// umschließt: Für jede Kante des Umrisses wird ein Rechteck parallel zu ihr
/// gelegt, das mit der kleinsten Fläche gewinnt.
Pitch? pitchFromPolygon(List<LatLng> polygon) {
  if (polygon.length < 3) return null;

  // In Meter umrechnen, Ursprung im Mittelpunkt der Eckpunkte
  final lat0 = polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
  final lon0 = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
  const mPerDegLat = 111320.0;
  final mPerDegLon = mPerDegLat * cos(lat0 * pi / 180);
  final pts = polygon
      .map((p) => Point<double>(
            (p.longitude - lon0) * mPerDegLon, // Osten
            (p.latitude - lat0) * mPerDegLat, // Norden
          ))
      .toList();

  double? bestArea, bestAngle, bestW, bestH;
  Point<double>? bestCenter;

  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    if (a == b) continue; // OSM wiederholt den ersten Punkt am Ende
    final angle = atan2(b.y - a.y, b.x - a.x);
    final c = cos(angle), s = sin(angle);

    // Alle Punkte so drehen, dass diese Kante waagrecht liegt
    var minU = double.infinity, maxU = -double.infinity;
    var minV = double.infinity, maxV = -double.infinity;
    for (final p in pts) {
      final u = p.x * c + p.y * s;
      final v = -p.x * s + p.y * c;
      minU = min(minU, u);
      maxU = max(maxU, u);
      minV = min(minV, v);
      maxV = max(maxV, v);
    }
    final w = maxU - minU, h = maxV - minV;
    if (bestArea == null || w * h < bestArea) {
      bestArea = w * h;
      bestAngle = angle;
      bestW = w;
      bestH = h;
      // Mitte des Rechtecks zurückdrehen
      final cu = (minU + maxU) / 2, cv = (minV + maxV) / 2;
      bestCenter = Point(cu * c - cv * s, cu * s + cv * c);
    }
  }
  if (bestArea == null) return null;

  // Die längere Seite ist die Längsachse (von Tor zu Tor)
  var angle = bestAngle!;
  var length = bestW!, width = bestH!;
  if (width > length) {
    (length, width) = (width, length);
    angle += pi / 2;
  }
  // Auf -90° … 90° bringen. Welches Tor „vorne“ ist, weiß man aus dem Umriss
  // ohnehin nicht.
  var deg = angle * 180 / pi;
  while (deg > 90) {
    deg -= 180;
  }
  while (deg <= -90) {
    deg += 180;
  }

  return Pitch(
    centerLat: lat0 + bestCenter!.y / mPerDegLat,
    centerLon: lon0 + bestCenter.x / mPerDegLon,
    rotationDeg: deg,
    length: length,
    width: width,
  );
}

/// Liegt der Punkt auf dem Platz? [marginM] erlaubt etwas Spielraum
/// außerhalb der Linien (Einwurf, Ecke, GPS-Ungenauigkeit).
bool pitchContains(Pitch pitch, double lat, double lon, {double marginM = 3}) {
  final p = pitch.toPitchMeters(lat, lon);
  return p.dx >= -marginM &&
      p.dy >= -marginM &&
      p.dx <= pitch.length + marginM &&
      p.dy <= pitch.width + marginM;
}

/// Wählt aus mehreren Plätzen den, auf dem die meisten Punkte der Einheit
/// liegen. So wird bei mehreren Plätzen nebeneinander der richtige genommen.
///
/// Liegt auf keinem Platz mindestens [minShare] der Punkte (z. B. Lauf im
/// Park), gibt es kein Ergebnis.
Pitch? choosePitch(
  List<Pitch> candidates,
  List<SensorData> points, {
  double minShare = 0.25,
}) {
  if (points.isEmpty) return null;
  // Für die Zählung reicht jeder 5. Punkt (1 pro Sekunde), das ist schneller
  final sample = [for (var i = 0; i < points.length; i += 5) points[i]];

  Pitch? best;
  var bestCount = 0;
  for (final pitch in candidates) {
    final count = sample.where((p) => pitchContains(pitch, p.latitude, p.longitude)).length;
    if (count > bestCount) {
      best = pitch;
      bestCount = count;
    }
  }
  return bestCount >= sample.length * minShare ? best : null;
}

/// Schwerpunkt der Punkte, als Mitte für die Suche in OpenStreetMap
LatLng centroid(List<SensorData> points) {
  final lat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  final lon = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
  return LatLng(lat, lon);
}
