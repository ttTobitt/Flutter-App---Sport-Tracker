import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/providers/tracker_sync.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/pitch_service.dart';
import 'package:sporttrackerflutterapp/services/session_database.dart';
import 'package:sporttrackerflutterapp/services/tracker_client.dart';
import 'package:sporttrackerflutterapp/services/tracker_protocol.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_tracker.dart';

class FakePitchService extends PitchService {
  @override
  Future<List<List<LatLng>>> findPitchesAround(LatLng center, {int radiusInMeters = 300}) async =>
      [MockSessionGenerator.hartnerPolygon];
}

/// 10 min Training mit 5 Hz = 3000 Punkte
final _start = DateTime(2026, 10, 29, 18, 30);
final _points = MockSessionGenerator.generate(
  id: 1,
  start: _start,
  duration: const Duration(minutes: 10),
).points;

void main() {
  group('Protokoll', () {
    test('Befehle werden richtig in Bytes verwandelt', () {
      expect(TrackerProtocol.listCommand(), [0x01]);
      expect(TrackerProtocol.getCommand(0x0102), [0x02, 0x02, 0x01]); // Little Endian
      expect(TrackerProtocol.deleteCommand(7), [0x03, 0x07, 0x00]);
    });

    test('Listeneintrag aus dem Beispiel im BLE-Protokoll', () {
      // 81 0100 907BE36A DC050000
      final m = TrackerMessage.decode(
          [0x81, 0x01, 0x00, 0x90, 0x7B, 0xE3, 0x6A, 0xDC, 0x05, 0x00, 0x00]);
      final info = (m as ListEntry).info;
      expect(info.id, 1);
      expect(info.start.toUtc(), DateTime.utc(2026, 10, 29, 17));
      expect(info.pointCount, 1500);
    });

    test('Punkt wird in Grad und km/h umgerechnet', () {
      final m = TrackerMessage.decode([
        0x84, 0x05, 0x00, // Paket Nr. 5
        0xC8, 0x00, 0x00, 0x00, // 200 ms
        0x9C, 0x7E, 0xB7, 0x1C, // 481 787 548 → 48,1787548°
        0x10, 0xEF, 0x93, 0x09, // 160 689 936 → 16,0689936°
        0xFA, 0x00, // 250 cm/s
        0x00, 0x00,
      ]) as PointsPacket;
      expect(m.seq, 5);
      final p = m.points.single.toSensorData(_start);
      expect(p.timestamp, _start.add(const Duration(milliseconds: 200)));
      expect(p.latitude, closeTo(48.1787548, 1e-9));
      expect(p.longitude, closeTo(16.0689936, 1e-9));
      expect(p.speedKmh, closeTo(9.0, 1e-9)); // 2,5 m/s
    });

    test('Kaputte Nachrichten werden erkannt', () {
      expect(() => TrackerMessage.decode([]), throwsFormatException);
      expect(() => TrackerMessage.decode([0x81, 0x01]), throwsFormatException);
      expect(() => TrackerMessage.decode([0x84, 0, 0, 1, 2, 3]), throwsFormatException);
      expect(() => TrackerMessage.decode([0x42]), throwsFormatException);
    });
  });

  group('TrackerClient', () {
    test('Liste holen und Einheit vollständig laden', () async {
      final tracker = FakeTracker()..addSession(1, _points);
      final client = TrackerClient(tracker);

      final list = await client.listSessions();
      expect(list.single.id, 1);
      expect(list.single.pointCount, 3000);
      expect(list.single.start, _start);

      final progress = <int>[];
      final points = await client.download(list.single, onProgress: (r, _) => progress.add(r));
      expect(points.length, 3000);
      expect(progress.length, 200); // 3000 / 15 Punkte pro Paket
      expect(points.last.timestamp, _points.last.timestamp);
      expect(points[1234].latitude, closeTo(_points[1234].latitude, 1e-7));
      expect(points[1234].speedKmh, closeTo(_points[1234].speedKmh, 0.02));
    });

    test('Auch mit kleiner MTU (1 Punkt pro Paket)', () async {
      final tracker = FakeTracker()
        ..addSession(1, _points)
        ..pointsPerPacket = 1;
      final client = TrackerClient(tracker);
      final points = await client.download((await client.listSessions()).single);
      expect(points.length, 3000);
    });

    test('Verlorenes Paket wird erkannt', () async {
      final tracker = FakeTracker()
        ..addSession(1, _points)
        ..dropOnce = {17};
      final client = TrackerClient(tracker);
      final info = (await client.listSessions()).single;
      await expectLater(client.download(info), throwsA(isA<IncompleteTransferException>()));
      // Beim zweiten Versuch kommt alles an
      expect((await client.download(info)).length, 3000);
    });

    test('Fehler vom Tracker und Timeout', () async {
      final tracker = FakeTracker();
      final client = TrackerClient(tracker, timeout: const Duration(milliseconds: 50));
      await expectLater(
        client.deleteSession(9),
        throwsA(isA<TrackerException>().having((e) => e.message, 'message', contains('Einheit 9'))),
      );
      tracker.silent = true;
      await expectLater(
        client.listSessions(),
        throwsA(isA<TrackerException>().having((e) => e.message, 'message', contains('Keine Antwort'))),
      );
    });
  });

  group('TrackerSync', () {
    sqfliteFfiInit();
    late Directory tempDir;
    late SessionDatabase db;
    late SessionProvider sessions;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sporttracker_sync');
      db = await SessionDatabase.open(factory: databaseFactoryFfi, path: '${tempDir.path}/t.db');
      sessions = SessionProvider(db, pitchService: FakePitchService());
    });
    tearDown(() async {
      // Platzsuchen im Hintergrund fertig werden lassen, dann aufräumen
      await Future.wait(sessions.sessions.map((s) => sessions.detectPitch(s.id)));
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('Überträgt alle Einheiten, speichert sie und löscht sie am Tracker', () async {
      final second = MockSessionGenerator.generate(
        id: 2,
        start: _start.add(const Duration(days: 1)),
        duration: const Duration(minutes: 5),
      ).points;
      final tracker = FakeTracker()
        ..addSession(1, _points)
        ..addSession(2, second)
        ..dropOnce = {3}; // erste Übertragung unvollständig → wird wiederholt
      final sync = TrackerSync(sessions);

      await sync.check(TrackerClient(tracker));
      expect(sync.state, SyncState.ready);
      expect(sync.pending.length, 2);

      await sync.transfer();
      expect(sync.state, SyncState.done, reason: sync.error);
      expect(sync.transferred, 2);
      expect(sync.pending, isEmpty);
      expect(tracker.sessions, isEmpty); // am Tracker gelöscht

      // In der App, neueste zuerst, mit allen Punkten
      expect(sessions.sessions.map((s) => s.points.length), [1500, 3000]);
      expect(sessions.sessions.last.start, _start);

      // Erst nach dem Speichern gelöscht: GET 1, GET 1 (Wiederholung), DELETE 1, …
      expect(tracker.commands.map((c) => c[0]), [0x01, 0x02, 0x02, 0x03, 0x02, 0x03]);
    });

    test('Schon vorhandene Einheit wird nicht doppelt gespeichert', () async {
      // So, als wäre beim letzten Mal nach dem Speichern die Verbindung abgerissen
      await sessions.addReceivedSession(_points);
      final tracker = FakeTracker()..addSession(1, _points);
      final sync = TrackerSync(sessions);

      await sync.check(TrackerClient(tracker));
      await sync.transfer();
      expect(sync.state, SyncState.done);
      expect(sessions.sessions.length, 1);
      expect(tracker.sessions, isEmpty);
    });

    test('Bleibt eine Einheit unvollständig, wird sie nicht gelöscht', () async {
      // Bei jedem Versuch geht ein Paket verloren
      final tracker = FakeTracker()..addSession(1, _points);
      final sync = TrackerSync(sessions);
      await sync.check(TrackerClient(_DropEveryTime(tracker)));
      await sync.transfer();

      expect(sync.state, SyncState.error);
      expect(sync.error, contains('verloren'));
      expect(sessions.sessions, isEmpty);
      expect(tracker.sessions.length, 1); // noch am Tracker
      expect(tracker.commands.where((c) => c[0] == 0x02).length, TrackerSync.maxAttempts);
    });
  });
}

/// Leitet alles an den FakeTracker weiter, lässt aber vor jedem GET Paket 0
/// verloren gehen
class _DropEveryTime implements TrackerLink {
  final FakeTracker tracker;
  _DropEveryTime(this.tracker);

  @override
  Stream<List<int>> get notifications => tracker.notifications;

  @override
  Future<void> write(List<int> command) {
    if (command[0] == TrackerProtocol.cmdGet) tracker.dropOnce = {0};
    return tracker.write(command);
  }
}
