import 'dart:async';

import '../models/sensor_data.dart';
import 'tracker_protocol.dart';

/// Die Leitung zum Tracker: Befehle schreiben, Notifications empfangen.
///
/// Im echten Betrieb steckt Bluetooth dahinter (`BleService`), in den Tests
/// ein nachgebauter Tracker. So lässt sich der ganze Ablauf ohne Hardware
/// testen.
abstract class TrackerLink {
  /// Alle Notifications der Daten-Characteristic. Muss ein Broadcast-Stream
  /// sein, weil jede Anfrage ihn neu abonniert.
  Stream<List<int>> get notifications;

  Future<void> write(List<int> command);
}

class TrackerException implements Exception {
  final String message;
  const TrackerException(this.message);

  @override
  String toString() => message;
}

/// Die Einheit ist nicht vollständig angekommen. Sie wird dann nochmal
/// angefordert und am Tracker auf keinen Fall gelöscht.
class IncompleteTransferException extends TrackerException {
  const IncompleteTransferException(super.message);
}

/// Spricht mit dem Tracker nach dem Protokoll in vault/BLE-Protokoll.md:
/// Befehl schicken, auf die passenden Antworten warten, Vollständigkeit
/// prüfen.
class TrackerClient {
  final TrackerLink _link;

  /// So lange darf der Tracker zwischen zwei Nachrichten schweigen. Gilt pro
  /// Nachricht, nicht für die ganze Übertragung (ein Spiel dauert länger).
  final Duration timeout;

  TrackerClient(this._link, {this.timeout = const Duration(seconds: 5)});

  /// Liste aller Einheiten, die am Tracker gespeichert sind
  Future<List<TrackerSessionInfo>> listSessions() {
    final entries = <TrackerSessionInfo>[];
    return _request(TrackerProtocol.listCommand(), (message, done) {
      switch (message) {
        case ListEntry(:final info):
          entries.add(info);
        case ListEnd(:final count):
          if (count != entries.length) {
            throw TrackerException('Liste unvollständig: $count angekündigt, ${entries.length} erhalten');
          }
          done.complete(entries);
        default:
          break; // gehört nicht zu dieser Anfrage
      }
    });
  }

  /// Alle Punkte einer Einheit holen. Wirft [IncompleteTransferException],
  /// wenn ein Paket fehlt oder die Anzahl nicht stimmt.
  ///
  /// [onProgress] wird nach jedem Paket mit (empfangen, angekündigt) aufgerufen.
  Future<List<SensorData>> download(
    TrackerSessionInfo info, {
    void Function(int received, int total)? onProgress,
  }) {
    var announced = -1; // noch kein SESSION_BEGIN
    var nextSeq = 0;
    var gap = false;
    final points = <SensorData>[];

    return _request(TrackerProtocol.getCommand(info.id), (message, done) {
      switch (message) {
        case SessionBegin(:final id, :final pointCount) when id == info.id:
          announced = pointCount;
        case PointsPacket(:final seq, points: final received) when announced >= 0:
          // Fehlt ein Paket, nicht sofort abbrechen: Der Tracker sendet sonst
          // weiter und wäre für die nächste Anfrage noch beschäftigt. Erst
          // am Ende melden.
          if (seq != nextSeq) gap = true;
          nextSeq = (seq + 1) & 0xFFFF; // u16 läuft nach 65535 über
          points.addAll(received.map((p) => p.toSensorData(info.start)));
          onProgress?.call(points.length, announced);
        case SessionEnd(:final id, :final sent) when id == info.id:
          if (gap) {
            throw const IncompleteTransferException('Mindestens ein Paket ist verloren gegangen');
          }
          if (points.length != announced || sent != announced) {
            throw IncompleteTransferException(
                '$announced Punkte angekündigt, $sent gesendet, ${points.length} empfangen');
          }
          done.complete(points);
        default:
          break;
      }
    });
  }

  /// Einheit am Tracker löschen. Erst aufrufen, wenn sie in der App
  /// gespeichert ist.
  Future<void> deleteSession(int id) {
    return _request<void>(TrackerProtocol.deleteCommand(id), (message, done) {
      if (message case Deleted(id: final deleted) when deleted == id) done.complete();
    });
  }

  /// Befehl schicken und Antworten an [onMessage] weitergeben, bis diese
  /// `done` abschließt. Fehler vom Tracker, unverständliche Bytes und zu
  /// lange Stille beenden die Anfrage mit einer [TrackerException].
  Future<T> _request<T>(
    List<int> command,
    void Function(TrackerMessage message, Completer<T> done) onMessage,
  ) async {
    final done = Completer<T>();
    Timer? timer;

    void fail(TrackerException e) {
      if (!done.isCompleted) done.completeError(e);
    }

    void restartTimer() {
      timer?.cancel();
      timer = Timer(timeout, () => fail(const TrackerException('Keine Antwort vom Tracker')));
    }

    // Zuerst zuhören, dann schreiben. Sonst könnte die Antwort ankommen,
    // bevor jemand zuhört.
    final subscription = _link.notifications.listen((bytes) {
      if (done.isCompleted) return;
      restartTimer();
      try {
        final message = TrackerMessage.decode(bytes);
        if (message is TrackerError) throw TrackerException(message.description);
        onMessage(message, done);
      } on FormatException catch (e) {
        fail(TrackerException('Unverständliche Nachricht: ${e.message}'));
      } on TrackerException catch (e) {
        fail(e);
      }
    });

    try {
      restartTimer();
      await _link.write(command);
      return await done.future;
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }
}
