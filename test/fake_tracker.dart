import 'dart:async';
import 'dart:typed_data';

import 'package:sporttrackerflutterapp/models/sensor_data.dart';
import 'package:sporttrackerflutterapp/services/tracker_client.dart';
import 'package:sporttrackerflutterapp/services/tracker_protocol.dart';

/// Nachgebauter Tracker für die Tests. Antwortet auf Befehle so wie die
/// Firmware (Sport-Tracker/src/ble_sync.cpp), nur ohne Bluetooth.
class FakeTracker implements TrackerLink {
  final _notifications = StreamController<List<int>>.broadcast();

  /// Gespeicherte Einheiten: ID → (Startzeit, Punkte)
  final Map<int, (DateTime, List<TrackerPoint>)> sessions = {};

  int pointsPerPacket = 15;

  /// Diese Paketnummern gehen bei der nächsten Übertragung „verloren“
  Set<int> dropOnce = {};

  /// Antwortet gar nicht (für den Timeout-Test)
  bool silent = false;

  final List<List<int>> commands = [];

  void addSession(int id, List<SensorData> points) {
    final start = points.first.timestamp;
    sessions[id] = (
      // Der Tracker kennt die Startzeit nur auf die Sekunde genau
      DateTime.fromMillisecondsSinceEpoch(start.millisecondsSinceEpoch ~/ 1000 * 1000),
      [
        for (final p in points)
          TrackerPoint(
            p.timestamp.difference(start).inMilliseconds,
            (p.latitude * 1e7).round(),
            (p.longitude * 1e7).round(),
            (p.speedKmh / 0.036).round(),
          ),
      ],
    );
  }

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<void> write(List<int> command) async {
    commands.add(command);
    if (silent) return;
    final id = command.length >= 3 ? command[1] | command[2] << 8 : 0;
    switch (command[0]) {
      case TrackerProtocol.cmdList:
        for (final MapEntry(key: id, value: (start, points)) in sessions.entries) {
          _send(TrackerProtocol.msgListEntry, [
            ..._u16(id),
            ..._u32(start.millisecondsSinceEpoch ~/ 1000),
            ..._u32(points.length),
          ]);
        }
        _send(TrackerProtocol.msgListEnd, _u16(sessions.length));
      case TrackerProtocol.cmdGet:
        final session = sessions[id];
        if (session == null) return _send(TrackerProtocol.msgError, [2, ..._u16(id)]);
        final points = session.$2;
        _send(TrackerProtocol.msgSessionBegin, [..._u16(id), ..._u32(points.length)]);
        var seq = 0;
        for (var i = 0; i < points.length; i += pointsPerPacket) {
          final chunk = points.skip(i).take(pointsPerPacket);
          if (!dropOnce.remove(seq)) {
            _send(TrackerProtocol.msgPoints, [..._u16(seq), for (final p in chunk) ..._point(p)]);
          }
          seq++;
        }
        _send(TrackerProtocol.msgSessionEnd, [..._u16(id), ..._u32(points.length)]);
      case TrackerProtocol.cmdDelete:
        if (sessions.remove(id) == null) return _send(TrackerProtocol.msgError, [2, ..._u16(id)]);
        _send(TrackerProtocol.msgDeleted, _u16(id));
    }
  }

  void _send(int type, List<int> payload) => _notifications.add([type, ...payload]);

  static List<int> _u16(int v) => [v & 0xFF, v >> 8 & 0xFF];
  static List<int> _u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

  static List<int> _point(TrackerPoint p) => (ByteData(16)
        ..setUint32(0, p.timeMs, Endian.little)
        ..setInt32(4, p.lat, Endian.little)
        ..setInt32(8, p.lon, Endian.little)
        ..setUint16(12, p.speedCms, Endian.little))
      .buffer
      .asUint8List();
}
