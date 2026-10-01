import 'package:flutter/widgets.dart';

import '../models/session.dart';
import '../services/mock_session.dart';

/// Hält alle Einheiten, die in der App liegen.
///
/// Aktuell nur im Arbeitsspeicher. Später werden die Einheiten aus der
/// SQLite-Datenbank geladen und nach der BLE-Übertragung dort gespeichert.
class SessionProvider extends ChangeNotifier {
  final List<Session> _sessions = [];

  /// Neueste Einheit zuerst
  List<Session> get sessions => List.unmodifiable(_sessions);

  Session? get latest => _sessions.isEmpty ? null : _sessions.first;

  /// Legt eine Test-Einheit an. Jede neue liegt einen Tag vor der vorherigen,
  /// damit der Verlauf nach mehreren Tagen aussieht.
  void addMockSession() {
    final id = _sessions.length + 1;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 18, 30)
        .subtract(Duration(days: 2 * (id - 1)));
    _sessions.add(MockSessionGenerator.generate(
      id: id,
      start: start,
      duration: Duration(minutes: 75 + (id * 7) % 20),
    ));
    _sessions.sort((a, b) => b.start.compareTo(a.start));
    notifyListeners();
  }
}
