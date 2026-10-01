import 'package:flutter_test/flutter_test.dart';
import 'package:sporttrackerflutterapp/models/sensor_data.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/session_analysis.dart';

/// Baut eine gerade Strecke nach Norden mit 5 Hz und den angegebenen
/// Geschwindigkeiten (eine pro Messpunkt).
List<SensorData> straightRun(List<double> speedsKmh) {
  final start = DateTime(2026, 10, 1, 18, 30);
  final points = <SensorData>[];
  var lat = 48.0;
  for (var i = 0; i < speedsKmh.length; i++) {
    points.add(SensorData(
      timestamp: start.add(Duration(milliseconds: i * 200)),
      latitude: lat,
      longitude: 16.0,
      speedKmh: speedsKmh[i],
    ));
    // zurückgelegte Meter in 0,2 s → Grad nach Norden
    lat += speedsKmh[i] / 3.6 * 0.2 / 111195;
  }
  return points;
}

void main() {
  test('100 m mit 18 km/h ergeben 100 m Distanz', () {
    // 18 km/h = 5 m/s → 1 m pro Messpunkt → 101 Punkte = 100 m
    final a = SessionAnalysis(straightRun(List.filled(101, 18)));
    expect(a.distanceKm * 1000, closeTo(100, 0.5));
    expect(a.avgSpeedKmh, closeTo(18, 0.2));
  });

  test('Sprint wird ab 1 s über 20 km/h erkannt', () {
    final speeds = [
      ...List.filled(10, 10.0),
      ...List.filled(8, 24.0), // 1,4 s schnell → Sprint
      ...List.filled(10, 10.0),
      ...List.filled(3, 25.0), // nur 0,4 s → kein Sprint
      ...List.filled(10, 10.0),
    ];
    final a = SessionAnalysis(straightRun(speeds));
    expect(a.sprints.length, 1);
    expect(a.sprints.first.maxSpeedKmh, 24);
    expect(a.maxSpeedKmh, 25);
  });

  test('Zonenanteile ergeben zusammen 100 %', () {
    final a = SessionAnalysis(straightRun([5, 10, 15, 25]));
    expect(a.zoneShares, [0.25, 0.25, 0.25, 0.25]);
  });

  test('Beispiel-Einheit hat realistische Werte', () {
    final s = MockSessionGenerator.generate(
      id: 1,
      start: DateTime(2026, 10, 1, 18, 30),
    );
    final a = s.analysis;
    // ignore: avoid_print
    print('Mock: ${a.distanceKm.toStringAsFixed(2)} km, '
        '${a.sprints.length} Sprints, max ${a.maxSpeedKmh.toStringAsFixed(1)} km/h, '
        'Zonen ${a.zoneShares.map((z) => (z * 100).round()).toList()} %');
    expect(a.distanceKm, inInclusiveRange(4, 12));
    expect(a.sprints, isNotEmpty);
  });
}
