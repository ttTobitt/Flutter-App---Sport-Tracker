import 'package:flutter/widgets.dart';

import '../models/pitch.dart';
import '../models/session.dart';
import '../services/mock_session.dart';
import '../services/pitch_detection.dart';
import '../services/pitch_service.dart';

/// Stand der Platz-Erkennung einer Einheit
enum PitchStatus { searching, found, notFound }

/// Hält alle Einheiten, die in der App liegen.
///
/// Aktuell nur im Arbeitsspeicher. Später werden die Einheiten aus der
/// SQLite-Datenbank geladen und nach der BLE-Übertragung dort gespeichert.
class SessionProvider extends ChangeNotifier {
  final PitchService _pitchService;

  SessionProvider({PitchService? pitchService})
      : _pitchService = pitchService ?? PitchService();

  final List<Session> _sessions = [];
  final Map<int, PitchStatus> _pitchStatus = {};

  /// Plätze, die schon einmal erkannt wurden. Bevor OpenStreetMap gefragt
  /// wird, wird hier geschaut. Der Spieler hat meist nur 1–2 Plätze.
  /// (Später in SQLite gespeichert, dann auch mit Korrekturen von Hand.)
  final List<Pitch> _knownPitches = [];

  /// Neueste Einheit zuerst
  List<Session> get sessions => List.unmodifiable(_sessions);

  Session? get latest => _sessions.isEmpty ? null : _sessions.first;

  Session sessionById(int id) => _sessions.firstWhere((s) => s.id == id);

  PitchStatus pitchStatusOf(int id) => _pitchStatus[id] ?? PitchStatus.notFound;

  /// Legt eine Test-Einheit an. Jede neue liegt zwei Tage vor der vorherigen,
  /// damit der Verlauf nach mehreren Tagen aussieht.
  void addMockSession() {
    final id = _sessions.length + 1;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 18, 30)
        .subtract(Duration(days: 2 * (id - 1)));
    _addSession(MockSessionGenerator.generate(
      id: id,
      start: start,
      duration: Duration(minutes: 75 + (id * 7) % 20),
    ));
  }

  void _addSession(Session session) {
    _sessions.add(session);
    _sessions.sort((a, b) => b.start.compareTo(a.start));
    notifyListeners();
    if (session.pitch == null) detectPitch(session.id);
  }

  /// Platz einer Einheit erkennen: erst bei den bekannten Plätzen schauen,
  /// sonst in OpenStreetMap suchen.
  Future<void> detectPitch(int id) async {
    final session = sessionById(id);
    _pitchStatus[id] = PitchStatus.searching;
    notifyListeners();

    var pitch = choosePitch(_knownPitches, session.points);
    if (pitch == null) {
      final polygons = await _pitchService.findPitchesAround(centroid(session.points));
      final candidates = polygons.map(pitchFromPolygon).whereType<Pitch>().toList();
      pitch = choosePitch(candidates, session.points);
      if (pitch != null) _knownPitches.add(pitch);
    }

    _replace(session.withPitch(pitch));
    _pitchStatus[id] = pitch == null ? PitchStatus.notFound : PitchStatus.found;
    notifyListeners();
  }

  void _replace(Session updated) {
    final i = _sessions.indexWhere((s) => s.id == updated.id);
    if (i >= 0) _sessions[i] = updated;
  }
}
