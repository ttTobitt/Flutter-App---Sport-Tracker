import 'dart:typed_data';

import '../models/sensor_data.dart';

/// Das Bluetooth-Protokoll zwischen Tracker und App: Befehle in Bytes
/// verwandeln und empfangene Bytes in Dart-Objekte.
///
/// Gegenstück zu `Sport-Tracker/src/protocol.h`, beschrieben in
/// vault/BLE-Protokoll.md. Ändert sich dort etwas, muss es hier auch
/// geändert werden. Alle Zahlen sind Little Endian.
class TrackerProtocol {
  // Befehle (App → Tracker)
  static const cmdList = 0x01;
  static const cmdGet = 0x02;
  static const cmdDelete = 0x03;

  // Nachrichten (Tracker → App)
  static const msgListEntry = 0x81;
  static const msgListEnd = 0x82;
  static const msgSessionBegin = 0x83;
  static const msgPoints = 0x84;
  static const msgSessionEnd = 0x85;
  static const msgDeleted = 0x86;
  static const msgError = 0xE0;

  static const pointSize = 16;
  static const pointsHeader = 3;

  static List<int> listCommand() => const [cmdList];
  static List<int> getCommand(int id) => [cmdGet, id & 0xFF, id >> 8];
  static List<int> deleteCommand(int id) => [cmdDelete, id & 0xFF, id >> 8];
}

/// Eine Einheit, wie sie in der Liste des Trackers steht
class TrackerSessionInfo {
  final int id;
  final DateTime start;
  final int pointCount;

  const TrackerSessionInfo({required this.id, required this.start, required this.pointCount});
}

/// Ein Punkt, wie er vom Tracker kommt (16 Byte)
class TrackerPoint {
  final int timeMs; // ms seit Start der Einheit
  final int lat; // Grad × 10^7
  final int lon; // Grad × 10^7
  final int speedCms; // cm/s

  const TrackerPoint(this.timeMs, this.lat, this.lon, this.speedCms);

  /// Umrechnung in das Format, mit dem der Rest der App arbeitet
  SensorData toSensorData(DateTime start) => SensorData(
        timestamp: start.add(Duration(milliseconds: timeMs)),
        latitude: lat / 1e7,
        longitude: lon / 1e7,
        speedKmh: speedCms * 0.036, // cm/s → km/h
      );
}

/// Alle Nachrichten, die der Tracker schicken kann. `sealed`: Dart weiß, dass
/// es nur diese gibt, und warnt bei einem `switch`, wenn eine fehlt.
sealed class TrackerMessage {
  const TrackerMessage();

  /// Bytes einer Notification → Nachricht. Wirft [FormatException], wenn die
  /// Bytes nicht zum Protokoll passen.
  factory TrackerMessage.decode(List<int> bytes) {
    if (bytes.isEmpty) throw const FormatException('Leere Nachricht');
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    int u16(int o) => data.getUint16(o, Endian.little);
    int u32(int o) => data.getUint32(o, Endian.little);
    void needLength(int n) {
      if (bytes.length < n) {
        throw FormatException('Nachricht 0x${bytes[0].toRadixString(16)} zu kurz: ${bytes.length} Byte');
      }
    }

    switch (bytes[0]) {
      case TrackerProtocol.msgListEntry:
        needLength(11);
        return ListEntry(TrackerSessionInfo(
          id: u16(1),
          start: DateTime.fromMillisecondsSinceEpoch(u32(3) * 1000, isUtc: true).toLocal(),
          pointCount: u32(7),
        ));
      case TrackerProtocol.msgListEnd:
        needLength(3);
        return ListEnd(u16(1));
      case TrackerProtocol.msgSessionBegin:
        needLength(7);
        return SessionBegin(u16(1), u32(3));
      case TrackerProtocol.msgPoints:
        needLength(TrackerProtocol.pointsHeader);
        final payload = bytes.length - TrackerProtocol.pointsHeader;
        if (payload % TrackerProtocol.pointSize != 0) {
          throw FormatException('Punkt-Paket mit $payload Byte, kein Vielfaches von 16');
        }
        return PointsPacket(u16(1), [
          for (var o = TrackerProtocol.pointsHeader; o < bytes.length; o += TrackerProtocol.pointSize)
            TrackerPoint(u32(o), data.getInt32(o + 4, Endian.little),
                data.getInt32(o + 8, Endian.little), u16(o + 12)),
        ]);
      case TrackerProtocol.msgSessionEnd:
        needLength(7);
        return SessionEnd(u16(1), u32(3));
      case TrackerProtocol.msgDeleted:
        needLength(3);
        return Deleted(u16(1));
      case TrackerProtocol.msgError:
        needLength(4);
        return TrackerError(bytes[1], u16(2));
      default:
        throw FormatException('Unbekannte Nachricht 0x${bytes[0].toRadixString(16)}');
    }
  }
}

class ListEntry extends TrackerMessage {
  final TrackerSessionInfo info;
  const ListEntry(this.info);
}

class ListEnd extends TrackerMessage {
  final int count;
  const ListEnd(this.count);
}

class SessionBegin extends TrackerMessage {
  final int id;
  final int pointCount;
  const SessionBegin(this.id, this.pointCount);
}

class PointsPacket extends TrackerMessage {
  final int seq; // laufende Nummer, zählt ab 0
  final List<TrackerPoint> points;
  const PointsPacket(this.seq, this.points);
}

class SessionEnd extends TrackerMessage {
  final int id;
  final int sent; // tatsächlich gesendete Punkte
  const SessionEnd(this.id, this.sent);
}

class Deleted extends TrackerMessage {
  final int id;
  const Deleted(this.id);
}

class TrackerError extends TrackerMessage {
  final int code;
  final int id;
  const TrackerError(this.code, this.id);

  String get description => switch (code) {
        1 => 'Tracker kennt den Befehl nicht',
        2 => 'Einheit $id gibt es am Tracker nicht',
        3 => 'Befehl zu kurz',
        4 => 'Tracker sendet gerade',
        _ => 'Unbekannter Fehler $code',
      };
}
