import 'package:flutter_test/flutter_test.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/stats.dart';

void main() {
  // Mittwoch, 18.11.2026 → Woche Mo 16.11. bis So 22.11.
  final wednesday = DateTime(2026, 11, 18, 12);

  final training = MockSessionGenerator.generate(
    id: 1,
    start: DateTime(2026, 11, 16, 18, 30), // Montag
    duration: const Duration(minutes: 30),
  );
  final match = MockSessionGenerator.generate(
    id: 2,
    start: DateTime(2026, 11, 22, 23, 0), // Sonntag spät, gehört noch dazu
    duration: const Duration(minutes: 95),
    isMatch: true,
  );
  final lastWeek = MockSessionGenerator.generate(
    id: 3,
    start: DateTime(2026, 11, 15, 23, 59), // Sonntag davor
    duration: const Duration(minutes: 20),
  );
  final all = [match, training, lastWeek];

  test('Woche: Montag 0 Uhr bis Sonntag 24 Uhr', () {
    expect(WeekSummary.mondayOf(wednesday), DateTime(2026, 11, 16));
    expect(
      WeekSummary.mondayOf(DateTime(2026, 11, 16)),
      DateTime(2026, 11, 16),
    );
    expect(
      WeekSummary.mondayOf(DateTime(2026, 11, 22, 23, 59)),
      DateTime(2026, 11, 16),
    );
  });

  test('Woche zählt nur Einheiten dieser Woche, Kilometer pro Tag', () {
    final w = WeekSummary.of(all, wednesday);
    expect(w.sessions, 2);
    final km = training.analysis.distanceKm + match.analysis.distanceKm;
    expect(w.km, closeTo(km, 1e-9));
    expect(
      w.sprints,
      training.analysis.sprints.length + match.analysis.sprints.length,
    );
    expect(
      w.kmPerDay[0],
      closeTo(training.analysis.distanceKm, 1e-9),
    ); // Montag
    expect(w.kmPerDay[6], closeTo(match.analysis.distanceKm, 1e-9)); // Sonntag
    expect(w.kmPerDay.sublist(1, 6), everyElement(0));
  });

  test('Leere Woche', () {
    final w = WeekSummary.of(all, DateTime(2026, 12, 2));
    expect(w.sessions, 0);
    expect(w.km, 0);
    expect(w.kmPerDay, everyElement(0));
  });

  test('Bestwerte kommen aus der richtigen Einheit', () {
    expect(Bests.of(const []), isNull);
    final b = Bests.of(all)!;
    // Das 95-min-Spiel ist am längsten und hat die meisten Kilometer
    expect(b.duration.session, same(match));
    expect(b.duration.value, closeTo(match.duration.inSeconds / 60, 1e-9));
    expect(b.distance.session, same(match));
    final fastest = all.reduce(
      (a, c) => c.analysis.maxSpeedKmh > a.analysis.maxSpeedKmh ? c : a,
    );
    expect(b.maxSpeed.value, fastest.analysis.maxSpeedKmh);
  });
}
