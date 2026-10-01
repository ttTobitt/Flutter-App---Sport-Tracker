import 'pitch.dart';
import 'sensor_data.dart';
import '../services/session_analysis.dart';

/// Eine aufgezeichnete Einheit (Training oder Spiel), so wie sie nach der
/// Übertragung vom Tracker in der App liegt.
class Session {
  final int id;
  final List<SensorData> points; // GPS-Messpunkte, ca. 5 pro Sekunde
  final Pitch? pitch; // Platz, auf dem gespielt wurde (falls erkannt)

  Session({required this.id, required this.points, this.pitch});

  DateTime get start => points.first.timestamp;
  DateTime get end => points.last.timestamp;
  Duration get duration => end.difference(start);

  /// Die Auswertung wird erst beim ersten Zugriff berechnet und dann gemerkt.
  late final SessionAnalysis analysis = SessionAnalysis(points);
}
