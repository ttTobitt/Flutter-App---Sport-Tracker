import 'dart:math';
import 'dart:ui';

/// Ein Fußballplatz in GPS-Koordinaten.
///
/// Wird gebraucht, um GPS-Punkte in Platz-Koordinaten (Meter) umzurechnen,
/// damit Heatmap und Laufweg auf einem gezeichneten Spielfeld landen.
/// Später kommen Mitte und Ausrichtung aus der Platz-Erkennung (Overpass),
/// siehe `pitch_service.dart`.
class Pitch {
  final double centerLat;
  final double centerLon;

  /// Richtung der Längsachse in Grad (0 = Ost-West, 90 = Nord-Süd)
  final double rotationDeg;

  final double length; // m
  final double width; // m

  const Pitch({
    required this.centerLat,
    required this.centerLon,
    this.rotationDeg = 0,
    this.length = 105,
    this.width = 68,
  });

  // Ungefähre Meter pro Grad. Auf einem Fußballplatz (ca. 100 m) ist der
  // Fehler dieser einfachen Umrechnung vernachlässigbar.
  static const _metersPerDegLat = 111320.0;
  double get _metersPerDegLon => _metersPerDegLat * cos(centerLat * pi / 180);

  /// GPS → Platz-Koordinaten. x: 0 … [length] (Torlinie zu Torlinie),
  /// y: 0 … [width] (Seitenlinie zu Seitenlinie).
  Offset toPitchMeters(double lat, double lon) {
    final east = (lon - centerLon) * _metersPerDegLon;
    final north = (lat - centerLat) * _metersPerDegLat;
    final r = rotationDeg * pi / 180;
    final along = east * cos(r) + north * sin(r);
    final across = -east * sin(r) + north * cos(r);
    return Offset(along + length / 2, width / 2 - across);
  }

  /// Platz-Koordinaten → GPS (Umkehrung von [toPitchMeters]). Wird von den
  /// Testdaten verwendet.
  (double lat, double lon) toGps(Offset p) {
    final along = p.dx - length / 2;
    final across = width / 2 - p.dy;
    final r = rotationDeg * pi / 180;
    final east = along * cos(r) - across * sin(r);
    final north = along * sin(r) + across * cos(r);
    return (
      centerLat + north / _metersPerDegLat,
      centerLon + east / _metersPerDegLon,
    );
  }
}
