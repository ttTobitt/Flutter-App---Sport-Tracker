import 'package:flutter_test/flutter_test.dart';
import 'package:sporttrackerflutterapp/models/sensor_data.dart';
import 'package:sporttrackerflutterapp/models/session.dart';
import 'package:sporttrackerflutterapp/services/halftime.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';

final _start = DateTime(2026, 10, 1, 18);

/// Einheit aus Abschnitten (Minuten, km/h), 5 Hz. km/h = null → keine Punkte
/// (z. B. kein GPS in der Kabine).
List<SensorData> phases(List<(int, double?)> parts) {
  final points = <SensorData>[];
  var ms = 0;
  for (final (minutes, kmh) in parts) {
    for (var i = 0; i < minutes * 60 * 5; i++) {
      if (kmh != null) {
        points.add(SensorData(
          timestamp: _start.add(Duration(milliseconds: ms)),
          latitude: 48,
          longitude: 16,
          speedKmh: kmh,
        ));
      }
      ms += 200;
    }
  }
  return points;
}

void main() {
  test('Spiel: Halbzeitpause wird gefunden', () {
    final s = MockSessionGenerator.generate(id: 2, start: _start, isMatch: true);
    final ht = detectHalftime(s.points)!;
    expect(ht.start.inMinutes, inInclusiveRange(44, 47));
    expect(ht.end.inMinutes, inInclusiveRange(58, 61));
  });

  test('Training: keine Halbzeitpause', () {
    final s = MockSessionGenerator.generate(id: 1, start: _start);
    expect(detectHalftime(s.points), isNull);
  });

  test('Pause ohne GPS-Punkte (Kabine) zählt auch', () {
    final ht = detectHalftime(phases([(45, 9), (15, null), (45, 9)]))!;
    expect(ht.start.inMinutes, 45);
    expect(ht.end.inMinutes, 60);
  });

  test('Lange Pause am Anfang (Aufwärmen, Besprechung) ist keine Halbzeit', () {
    expect(detectHalftime(phases([(20, 1), (90, 9)])), isNull);
  });

  test('Kurze Trinkpause ist keine Halbzeit', () {
    expect(detectHalftime(phases([(40, 9), (4, 1), (40, 9)])), isNull);
  });

  test('2. Halbzeit wird gedreht: Rechtsaußen bleibt rechts', () {
    final raw = MockSessionGenerator.generate(id: 2, start: _start, isMatch: true);
    final ht = raw.halftime!;
    final w = MockSessionGenerator.pitch.width;

    double meanY(Session s, bool secondHalf) {
      final ys = [
        for (var i = 0; i < s.pitchPositions.length; i++)
          if (secondHalf ? i > ht.endIndex : i < ht.startIndex) s.pitchPositions[i].dy,
      ];
      return ys.reduce((a, b) => a + b) / ys.length;
    }

    final asMatch = raw.withPitch(MockSessionGenerator.pitch).withType(SessionType.match);
    final asTraining = raw.withPitch(MockSessionGenerator.pitch);

    // Als Spiel: beide Halbzeiten rechts (y groß)
    expect(meanY(asMatch, false), greaterThan(w * 0.65));
    expect(meanY(asMatch, true), greaterThan(w * 0.65));
    // Als Training (nicht gedreht): 2. Halbzeit liegt auf der anderen Seite
    expect(meanY(asTraining, true), lessThan(w * 0.35));
  });
}
