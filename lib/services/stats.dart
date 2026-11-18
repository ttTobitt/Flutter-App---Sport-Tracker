import '../models/session.dart';

/// Zusammenfassung einer Kalenderwoche (Montag 0 Uhr bis Sonntag 24 Uhr)
class WeekSummary {
  final DateTime monday;
  final int sessions;
  final double km;
  final int sprints;

  /// Kilometer pro Wochentag, [0] = Montag … [6] = Sonntag
  final List<double> kmPerDay;

  const WeekSummary(
    this.monday,
    this.sessions,
    this.km,
    this.sprints,
    this.kmPerDay,
  );

  /// Montag 0 Uhr der Woche, in der [day] liegt
  static DateTime mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - 1));

  /// Woche, in der [day] liegt
  factory WeekSummary.of(List<Session> all, DateTime day) {
    final monday = mondayOf(day);
    // DateTime(…, day + 7) statt + Duration(days: 7): Bei der Umstellung auf
    // Sommer-/Winterzeit hat eine Woche nicht genau 7 × 24 Stunden
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    final perDay = List<double>.filled(7, 0);
    var count = 0, sprints = 0;
    var km = 0.0;
    for (final s in all) {
      if (s.start.isBefore(monday) || !s.start.isBefore(nextMonday)) continue;
      final a = s.analysis;
      count++;
      km += a.distanceKm;
      sprints += a.sprints.length;
      perDay[s.start.weekday - 1] += a.distanceKm;
    }
    return WeekSummary(monday, count, km, sprints, perDay);
  }
}

/// Ein Bestwert und die Einheit, in der er erreicht wurde
class Best {
  final Session session;
  final double value;
  const Best(this.session, this.value);
}

/// Bestwerte über alle Einheiten. null, wenn es noch keine Einheit gibt.
class Bests {
  final Best maxSpeed; // km/h
  final Best distance; // km
  final Best sprints; // Anzahl
  final Best duration; // Minuten

  const Bests(this.maxSpeed, this.distance, this.sprints, this.duration);

  static Bests? of(List<Session> all) {
    if (all.isEmpty) return null;
    Best best(double Function(Session) value) {
      var top = Best(all.first, value(all.first));
      for (final s in all.skip(1)) {
        final v = value(s);
        if (v > top.value) top = Best(s, v);
      }
      return top;
    }

    return Bests(
      best((s) => s.analysis.maxSpeedKmh),
      best((s) => s.analysis.distanceKm),
      best((s) => s.analysis.sprints.length.toDouble()),
      best((s) => s.duration.inSeconds / 60),
    );
  }
}
