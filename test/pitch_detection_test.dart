import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sporttrackerflutterapp/models/pitch.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/pitch_detection.dart';

void main() {
  test('Schräges Rechteck: Mitte, Maße und Winkel werden erkannt', () {
    // Platz 100 × 64 m, um 30° gedreht. Ecken mit Pitch.toGps erzeugen.
    const truth = Pitch(
      centerLat: 48.2,
      centerLon: 16.3,
      rotationDeg: 30,
      length: 100,
      width: 64,
    );
    final corners = [
      for (final c in const [Offset(0, 0), Offset(100, 0), Offset(100, 64), Offset(0, 64)])
        truth.toGps(c),
    ].map((g) => LatLng(g.$1, g.$2)).toList();

    final p = pitchFromPolygon(corners)!;
    expect(p.length, closeTo(100, 0.5));
    expect(p.width, closeTo(64, 0.5));
    expect(p.rotationDeg, closeTo(30, 0.5));
    expect(p.centerLat, closeTo(48.2, 1e-6));
    expect(p.centerLon, closeTo(16.3, 1e-6));
  });

  test('Hartner-Platz aus OSM hat plausible Maße', () {
    final p = pitchFromPolygon(MockSessionGenerator.hartnerPolygon)!;
    // ignore: avoid_print
    print('Hartner: ${p.length.toStringAsFixed(1)} × ${p.width.toStringAsFixed(1)} m, '
        '${p.rotationDeg.toStringAsFixed(1)}°');
    expect(p.length, inInclusiveRange(90, 110));
    expect(p.width, inInclusiveRange(50, 75));
  });

  test('Von zwei Plätzen nebeneinander wird der richtige gewählt', () {
    final session = MockSessionGenerator.generate(id: 1, start: DateTime(2026, 10, 1, 18));
    final hartner = pitchFromPolygon(MockSessionGenerator.hartnerPolygon)!;
    final neighbour = pitchFromPolygon(MockSessionGenerator.neighbourPolygon)!;

    final chosen = choosePitch([neighbour, hartner], session.points);
    expect(chosen, same(hartner));
  });

  test('Kein Platz, wenn die Einheit woanders stattfand', () {
    final session = MockSessionGenerator.generate(id: 1, start: DateTime(2026, 10, 1, 18));
    final neighbour = pitchFromPolygon(MockSessionGenerator.neighbourPolygon)!;
    expect(choosePitch([neighbour], session.points), isNull);
  });

  test('Mitte und Ecken landen an der richtigen Stelle im Feld', () {
    final p = pitchFromPolygon(MockSessionGenerator.hartnerPolygon)!;
    final mid = p.toPitchMeters(p.centerLat, p.centerLon);
    expect(mid.dx, closeTo(p.length / 2, 0.01));
    expect(mid.dy, closeTo(p.width / 2, 0.01));
    // Jede OSM-Ecke liegt (fast) auf einer Ecke des Feldes
    for (final c in MockSessionGenerator.hartnerPolygon) {
      final m = p.toPitchMeters(c.latitude, c.longitude);
      final toCorner = [
        m.distance,
        (m - Offset(p.length, 0)).distance,
        (m - Offset(0, p.width)).distance,
        (m - Offset(p.length, p.width)).distance,
      ].reduce(min);
      expect(toCorner, lessThan(3));
    }
  });
}
