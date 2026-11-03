import 'package:flutter/foundation.dart';

import '../models/sensor_data.dart';
import '../services/tracker_client.dart';
import '../services/tracker_protocol.dart';
import 'session_provider.dart';

enum SyncState {
  idle, // kein Tracker verbunden
  checking, // fragt die Liste ab
  ready, // Liste da, wartet auf „Übertragen“
  transferring,
  done,
  error,
}

/// Holt die Einheiten vom Tracker in die App.
///
/// Für jede Einheit: laden → prüfen → in SQLite speichern → erst dann am
/// Tracker löschen. Bricht etwas ab, bleibt die Einheit am Tracker und wird
/// beim nächsten Mal wieder angeboten. Siehe vault/BLE-Protokoll.md.
class TrackerSync extends ChangeNotifier {
  final SessionProvider _sessions;

  TrackerSync(this._sessions);

  /// So oft wird eine Einheit angefordert, wenn sie unvollständig ankommt
  static const maxAttempts = 3;

  TrackerClient? _client;
  SyncState _state = SyncState.idle;
  List<TrackerSessionInfo> _pending = const [];
  int _current = 0; // die wievielte Einheit gerade übertragen wird (ab 1)
  int _total = 0;
  double _progress = 0; // Fortschritt der aktuellen Einheit, 0 … 1
  int _transferred = 0;
  String _error = '';

  SyncState get state => _state;

  /// Einheiten, die noch am Tracker liegen
  List<TrackerSessionInfo> get pending => List.unmodifiable(_pending);
  int get current => _current;
  int get total => _total;
  double get progress => _progress;
  int get transferred => _transferred;
  String get error => _error;

  /// Nach dem Verbinden: nachsehen, was am Tracker liegt
  Future<void> check(TrackerClient client) async {
    _client = client;
    _set(SyncState.checking);
    try {
      _pending = await client.listSessions();
      _set(SyncState.ready);
    } catch (e) {
      _fail(e);
    }
  }

  /// Alle Einheiten aus [pending] übertragen
  Future<void> transfer() async {
    final client = _client;
    if (client == null || _state == SyncState.transferring) return;

    final todo = List.of(_pending);
    _total = todo.length;
    _transferred = 0;
    _set(SyncState.transferring);
    try {
      for (var i = 0; i < todo.length; i++) {
        final info = todo[i];
        _current = i + 1;
        _progress = 0;
        notifyListeners();

        final points = await _download(client, info);
        // Schon in der App? Passiert, wenn beim letzten Mal nach dem
        // Speichern, aber vor dem Löschen die Verbindung abgerissen ist.
        // Dann nicht nochmal speichern, nur am Tracker löschen.
        if (points.isNotEmpty && !_sessions.hasSessionStartingAt(points.first.timestamp)) {
          await _sessions.addReceivedSession(points);
        }
        await client.deleteSession(info.id);

        _pending = _pending.where((p) => p.id != info.id).toList();
        _transferred++;
      }
      _set(SyncState.done);
    } catch (e) {
      _fail(e);
    }
  }

  /// Nach einem Fehler: Liste neu abfragen. Was schon übertragen wurde, ist
  /// am Tracker gelöscht und taucht nicht mehr auf.
  Future<void> retry() async {
    final client = _client;
    if (client != null) await check(client);
  }

  /// Verbindung getrennt
  void reset() {
    _client = null;
    _pending = const [];
    _set(SyncState.idle);
  }

  Future<List<SensorData>> _download(TrackerClient client, TrackerSessionInfo info) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await client.download(info, onProgress: _onProgress);
      } on IncompleteTransferException {
        if (attempt >= maxAttempts) rethrow;
        _progress = 0;
        notifyListeners();
      }
    }
  }

  void _onProgress(int received, int total) {
    final progress = total == 0 ? 1.0 : received / total;
    // Nur bei jedem vollen Prozent neu zeichnen, nicht bei jedem Paket
    if ((progress * 100).floor() != (_progress * 100).floor()) {
      _progress = progress;
      notifyListeners();
    }
  }

  void _set(SyncState state) {
    _state = state;
    notifyListeners();
  }

  void _fail(Object e) {
    _error = e is TrackerException ? e.message : 'Verbindungsfehler: $e';
    _set(SyncState.error);
  }
}
