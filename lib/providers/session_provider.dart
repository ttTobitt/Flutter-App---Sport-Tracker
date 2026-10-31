import 'package:flutter/widgets.dart';

import '../models/pitch.dart';
import '../models/session.dart';
import '../services/mock_session.dart';
import '../services/pitch_detection.dart';
import '../services/pitch_service.dart';
import '../services/session_database.dart';

/// Stand der Platz-Erkennung einer Einheit
enum PitchStatus { searching, found, notFound }

/// Hält alle Einheiten, die in der App liegen.
///
/// Beim Start werden alle Einheiten und Plätze aus der Datenbank geladen
/// ([load]). Jede Änderung wird zuerst in der Datenbank gespeichert und erst
/// danach in der Liste hier, damit beides immer zusammenpasst.
class SessionProvider extends ChangeNotifier {
  final SessionDatabase _db;
  final PitchService _pitchService;

  SessionProvider(this._db, {PitchService? pitchService})
      : _pitchService = pitchService ?? PitchService();

  final List<Session> _sessions = [];
  final Map<int, PitchStatus> _pitchStatus = {};

  /// Laufende Platzsuchen. Wird für dieselbe Einheit nochmal gesucht (z. B.
  /// „Nochmal suchen“ während der Suche), gibt es dieselbe Suche zurück statt
  /// einer zweiten. Sonst würde derselbe Platz doppelt gespeichert.
  final Map<int, Future<void>> _runningDetections = {};

  /// Die zuletzt eingereihte Platzsuche, siehe [_queueDetection]
  Future<void> _lastDetection = Future.value();

  /// Plätze, die schon einmal erkannt oder von Hand festgelegt wurden, mit
  /// ihrer ID in der Datenbank. Bevor OpenStreetMap gefragt wird, wird hier
  /// geschaut. Der Spieler hat meist nur 1–2 Plätze.
  ///
  /// `Map.identity()`: Schlüssel ist das Pitch-Objekt selbst, nicht sein
  /// Inhalt. Einheiten auf demselben Platz teilen sich ein Objekt.
  final Map<Pitch, int> _pitchIds = Map.identity();

  /// Neueste Einheit zuerst
  List<Session> get sessions => List.unmodifiable(_sessions);

  Session? get latest => _sessions.isEmpty ? null : _sessions.first;

  Session sessionById(int id) => _sessions.firstWhere((s) => s.id == id);

  PitchStatus pitchStatusOf(int id) => _pitchStatus[id] ?? PitchStatus.notFound;

  /// Alle gespeicherten Einheiten und Plätze aus der Datenbank holen. Wird
  /// einmal beim Start der App aufgerufen.
  Future<void> load() async {
    final (pitches, sessions) = await _db.loadAll();
    _pitchIds
      ..clear()
      ..addAll({for (final e in pitches.entries) e.value: e.key});
    _sessions
      ..clear()
      ..addAll(sessions);
    for (final s in sessions) {
      if (s.pitch != null) _pitchStatus[s.id] = PitchStatus.found;
    }
    notifyListeners();
  }

  /// Legt eine Test-Einheit an. Jede neue liegt zwei Tage vor der vorherigen,
  /// damit der Verlauf nach mehreren Tagen aussieht. Jede zweite ist ein Spiel.
  Future<void> addMockSession() async {
    final n = _sessions.length + 1;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 18, 30)
        .subtract(Duration(days: 2 * (n - 1)));
    await _addSession(MockSessionGenerator.generate(
      id: n, // nur vorläufig, die echte ID vergibt die Datenbank
      start: start,
      duration: Duration(minutes: 75 + (n * 7) % 20),
      isMatch: n.isEven,
    ));
  }

  /// Neue Einheit speichern (später: direkt nach der BLE-Übertragung).
  /// Der Platz wird danach im Hintergrund gesucht.
  Future<void> _addSession(Session received) async {
    // Typ vorschlagen: Gibt es eine Halbzeitpause, ist es vermutlich ein Spiel.
    // Der Nutzer kann es im Detail-Screen ändern.
    if (received.halftime != null) received = received.withType(SessionType.match);
    final id = await _db.insertSession(received);
    final session = Session(id: id, points: received.points, type: received.type);
    _sessions.add(session);
    _sessions.sort((a, b) => b.start.compareTo(a.start));
    notifyListeners();
    detectPitch(id);
  }

  /// Platz einer Einheit erkennen: erst bei den bekannten Plätzen schauen,
  /// sonst in OpenStreetMap suchen.
  Future<void> detectPitch(int id) {
    // Wichtig: Callback mit { } statt =>. Mit => würde remove() den Future
    // selbst zurückgeben, whenComplete würde auf ihn warten → wartet ewig.
    return _runningDetections[id] ??= _queueDetection(id).whenComplete(() {
      _runningDetections.remove(id);
    });
  }

  /// Platzsuchen laufen nacheinander, nicht gleichzeitig. Sonst würden zwei
  /// Einheiten auf demselben (noch unbekannten) Platz beide OpenStreetMap
  /// fragen und den Platz zweimal speichern. Eine spätere Korrektur würde
  /// dann nur eine der beiden Kopien treffen.
  Future<void> _queueDetection(int id) {
    _pitchStatus[id] = PitchStatus.searching;
    notifyListeners();
    final previous = _lastDetection;
    return _lastDetection = () async {
      // Ist die vorherige Suche fehlgeschlagen, trotzdem weitermachen
      await previous.catchError((_) {});
      await _detectPitch(id);
    }();
  }

  Future<void> _detectPitch(int id) async {
    final session = sessionById(id);
    var pitch = choosePitch(_pitchIds.keys.toList(), session.points);
    if (pitch == null) {
      final polygons = await _pitchService.findPitchesAround(centroid(session.points));
      final candidates = polygons.map(pitchFromPolygon).whereType<Pitch>().toList();
      pitch = choosePitch(candidates, session.points);
      if (pitch != null) _pitchIds[pitch] = await _db.insertPitch(pitch);
    }

    await _db.setSessionPitch(id, pitch == null ? null : _pitchIds[pitch]);
    _replace(sessionById(id).withPitch(pitch));
    _pitchStatus[id] = pitch == null ? PitchStatus.notFound : PitchStatus.found;
    notifyListeners();
  }

  /// Platz von Hand korrigiert oder festgelegt. Gilt für alle Einheiten, die
  /// bisher denselben Platz hatten, und wird als bekannter Platz gemerkt.
  Future<void> setPitch(int sessionId, Pitch corrected) async {
    final old = sessionById(sessionId).pitch;
    final oldId = old == null ? null : _pitchIds[old];

    if (oldId != null) {
      // Bestehenden Platz überschreiben: In der Datenbank zeigen alle
      // Einheiten dort weiter auf dieselbe ID und haben damit den neuen.
      await _db.updatePitch(oldId, corrected);
      _pitchIds.remove(old);
      _pitchIds[corrected] = oldId;
    } else {
      final newId = await _db.insertPitch(corrected);
      await _db.setSessionPitch(sessionId, newId);
      _pitchIds[corrected] = newId;
    }

    for (final s in List.of(_sessions)) {
      if (s.id == sessionId || (old != null && identical(s.pitch, old))) {
        _replace(s.withPitch(corrected));
        _pitchStatus[s.id] = PitchStatus.found;
      }
    }
    notifyListeners();
  }

  /// Training oder Spiel von Hand festlegen
  Future<void> setType(int id, SessionType type) async {
    await _db.setSessionType(id, type);
    _replace(sessionById(id).withType(type));
    notifyListeners();
  }

  void _replace(Session updated) {
    final i = _sessions.indexWhere((s) => s.id == updated.id);
    if (i >= 0) _sessions[i] = updated;
  }
}
