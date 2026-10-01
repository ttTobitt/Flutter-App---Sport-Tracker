import 'dart:ui';

import 'pitch.dart';
import 'sensor_data.dart';
import '../services/halftime.dart';
import '../services/heatmap.dart';
import '../services/session_analysis.dart';

enum SessionType { training, match }

/// Eine aufgezeichnete Einheit (Training oder Spiel), so wie sie nach der
/// Übertragung vom Tracker in der App liegt.
class Session {
  final int id;
  final List<SensorData> points; // GPS-Messpunkte, ca. 5 pro Sekunde
  final Pitch? pitch; // Platz, auf dem gespielt wurde (falls erkannt)
  final SessionType type;

  Session({
    required this.id,
    required this.points,
    this.pitch,
    this.type = SessionType.training,
  });

  /// Kopien mit geändertem Platz bzw. Typ. Es wird eine neue Session angelegt
  /// statt die alte zu ändern, weil Heatmap & Co. davon abhängen und nur
  /// einmal berechnet werden.
  Session withPitch(Pitch? pitch) =>
      Session(id: id, points: points, pitch: pitch, type: type);

  Session withType(SessionType type) =>
      Session(id: id, points: points, pitch: pitch, type: type);

  DateTime get start => points.first.timestamp;
  DateTime get end => points.last.timestamp;
  Duration get duration => end.difference(start);

  bool get isMatch => type == SessionType.match;

  /// Die Auswertung wird erst beim ersten Zugriff berechnet und dann gemerkt.
  late final SessionAnalysis analysis = SessionAnalysis(points);

  /// Halbzeitpause, falls eine gefunden wird. Wird unabhängig vom Typ
  /// gesucht, damit die App „Spiel“ vorschlagen kann.
  late final Halftime? halftime = detectHalftime(points);

  /// Wird die 2. Halbzeit gedreht? Nur bei Spielen mit erkannter Halbzeit.
  bool get turnsSecondHalf => isMatch && halftime != null;

  /// Alle Punkte in Metern auf dem Platz, so ausgerichtet, dass immer in
  /// dieselbe Richtung angegriffen wird. Leer, wenn kein Platz bekannt ist.
  ///
  /// Nach dem Seitenwechsel spielt die Mannschaft aufs andere Tor. Damit die
  /// Heatmap trotzdem zusammenpasst, wird die 2. Halbzeit um 180° um die
  /// Feldmitte gedreht (nicht nur links/rechts gespiegelt): So bleibt z. B.
  /// ein Rechtsaußen auch in der 2. Halbzeit auf der rechten Seite.
  late final List<Offset> pitchPositions = _pitchPositions();

  List<Offset> _pitchPositions() {
    final p = pitch;
    if (p == null) return const [];
    final turnAfter = turnsSecondHalf ? halftime!.endIndex : points.length;
    return [
      for (var i = 0; i < points.length; i++)
        if (i > turnAfter)
          _turn(p.toPitchMeters(points[i].latitude, points[i].longitude), p)
        else
          p.toPitchMeters(points[i].latitude, points[i].longitude),
    ];
  }

  static Offset _turn(Offset m, Pitch p) => Offset(p.length - m.dx, p.width - m.dy);

  /// Gehört der Punkt zur Halbzeitpause eines Spiels? Solche Punkte kommen
  /// nicht in Heatmap und Laufweg (Weg in die Kabine, Herumstehen).
  bool isInBreak(int index) => turnsSecondHalf && halftime!.contains(index);

  late final HeatmapGrid? heatmap = pitch == null
      ? null
      : HeatmapGrid.compute(
          [
            for (var i = 0; i < pitchPositions.length; i++)
              if (!isInBreak(i)) pitchPositions[i],
          ],
          pitchLength: pitch!.length,
          pitchWidth: pitch!.width,
        );
}
