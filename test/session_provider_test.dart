import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sporttrackerflutterapp/models/pitch.dart';
import 'package:sporttrackerflutterapp/models/session.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/pitch_service.dart';
import 'package:sporttrackerflutterapp/services/session_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Liefert feste Plätze statt OpenStreetMap zu fragen und zählt die Anfragen
class FakePitchService extends PitchService {
  int requests = 0;

  @override
  Future<List<List<LatLng>>> findPitchesAround(LatLng center, {int radiusInMeters = 300}) async {
    requests++;
    return [MockSessionGenerator.neighbourPolygon, MockSessionGenerator.hartnerPolygon];
  }
}

void main() {
  // SQLite-Variante für den PC (am Handy übernimmt das Android)
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sporttracker_test');
    dbPath = '${tempDir.path}/test.db';
  });
  tearDown(() => tempDir.delete(recursive: true));

  Future<SessionDatabase> openDb() =>
      SessionDatabase.open(factory: databaseFactoryFfi, path: dbPath);

  test('Platz wird erkannt, Korrektur gilt für alle Einheiten dort', () async {
    final fake = FakePitchService();
    final db = await openDb();
    final provider = SessionProvider(db, pitchService: fake);

    await provider.addMockSession();
    await provider.detectPitch(1);
    expect(provider.pitchStatusOf(1), PitchStatus.found);
    expect(provider.sessionById(1).pitch!.length, closeTo(102.5, 0.5));

    // Zweite Einheit am selben Platz: kommt aus den bekannten Plätzen
    await provider.addMockSession();
    await provider.detectPitch(2);
    expect(identical(provider.sessionById(2).pitch, provider.sessionById(1).pitch), isTrue);

    // Von Hand korrigieren → beide Einheiten bekommen den neuen Platz
    final old = provider.sessionById(1).pitch!;
    final corrected = Pitch(
      centerLat: old.centerLat,
      centerLon: old.centerLon,
      rotationDeg: old.rotationDeg + 1,
      length: 100,
      width: 62,
      fromOsm: true,
    );
    await provider.setPitch(1, corrected);
    expect(provider.sessionById(1).pitch, same(corrected));
    expect(provider.sessionById(2).pitch, same(corrected));

    // Dritte Einheit nutzt den korrigierten Platz, ohne OSM zu fragen
    final before = fake.requests;
    await provider.addMockSession();
    await provider.detectPitch(3);
    expect(provider.sessionById(3).pitch, same(corrected));
    expect(fake.requests, before);
    await db.close();
  });

  test('Mit Halbzeitpause wird „Spiel“ vorgeschlagen, sonst „Training“', () async {
    final db = await openDb();
    final provider = SessionProvider(db, pitchService: FakePitchService());
    await provider.addMockSession(); // Training
    await provider.addMockSession(); // Spiel mit Halbzeit
    expect(provider.sessionById(1).type, SessionType.training);
    expect(provider.sessionById(2).type, SessionType.match);

    // Von Hand umstellen
    await provider.setType(2, SessionType.training);
    expect(provider.sessionById(2).type, SessionType.training);
    expect(provider.sessionById(2).turnsSecondHalf, isFalse);
    await Future.wait([provider.detectPitch(1), provider.detectPitch(2)]);
    await db.close();
  });

  test('Gelöschte Einheit ist weg, auch nach Neustart, der Platz bleibt', () async {
    var db = await openDb();
    final fake = FakePitchService();
    final provider = SessionProvider(db, pitchService: fake);
    await provider.addMockSession();
    await provider.addMockSession();
    await Future.wait([provider.detectPitch(1), provider.detectPitch(2)]);

    await provider.deleteSession(1);
    expect(provider.sessions.map((s) => s.id), [2]);
    expect(provider.findSession(1), isNull);
    await db.close();

    db = await openDb();
    final after = SessionProvider(db, pitchService: fake);
    await after.load();
    expect(after.sessions.map((s) => s.id), [2]);

    // Neue Einheit am selben Platz: Platz ist noch bekannt, keine OSM-Anfrage
    final before = fake.requests;
    await after.addMockSession();
    final newId = after.latest!.id;
    await after.detectPitch(newId);
    expect(after.sessionById(newId).pitch, same(after.sessionById(2).pitch));
    expect(fake.requests, before);
    await db.close();
  });

  test('Löschen während der Platzsuche führt zu keinem Fehler', () async {
    final db = await openDb();
    final provider = SessionProvider(db, pitchService: FakePitchService());
    await provider.addMockSession(); // startet die Platzsuche im Hintergrund
    final search = provider.detectPitch(1);
    await provider.deleteSession(1);
    await search;
    expect(provider.sessions, isEmpty);
    await db.close();
  });

  test('Nach Neustart der App sind Einheiten, Typ und Platz noch da', () async {
    var db = await openDb();
    final before = SessionProvider(db, pitchService: FakePitchService());
    await before.addMockSession();
    await before.addMockSession();
    await Future.wait([before.detectPitch(1), before.detectPitch(2)]);
    await before.setType(1, SessionType.match);

    final pitch = before.sessionById(1).pitch!;
    final corrected = Pitch(
      centerLat: pitch.centerLat,
      centerLon: pitch.centerLon,
      rotationDeg: pitch.rotationDeg,
      length: 98,
      width: 60,
      fromOsm: true,
    );
    await before.setPitch(1, corrected);
    await db.close();

    // „Neustart“: neue Verbindung, neuer Provider, alles aus der Datei laden
    db = await openDb();
    final after = SessionProvider(db, pitchService: FakePitchService());
    await after.load();

    expect(after.sessions.map((s) => s.id), [1, 2]);
    expect(after.sessionById(1).type, SessionType.match);
    expect(after.sessionById(2).type, SessionType.match); // Halbzeit erkannt

    // Beide Einheiten haben den korrigierten Platz, als dasselbe Objekt
    final p1 = after.sessionById(1).pitch!;
    expect(p1.length, 98);
    expect(p1.width, 60);
    expect(p1.fromOsm, isTrue);
    expect(after.sessionById(2).pitch, same(p1));
    expect(after.pitchStatusOf(1), PitchStatus.found);

    // GPS-Punkte: gleiche Anzahl, Werte bis auf die gespeicherte Genauigkeit
    for (final id in [1, 2]) {
      final a = before.sessionById(id).points;
      final b = after.sessionById(id).points;
      expect(b.length, a.length);
      for (final i in [0, a.length ~/ 2, a.length - 1]) {
        expect(b[i].timestamp, a[i].timestamp);
        expect(b[i].latitude, closeTo(a[i].latitude, 1e-7));
        expect(b[i].longitude, closeTo(a[i].longitude, 1e-7));
        expect(b[i].speedKmh, closeTo(a[i].speedKmh, 1e-3));
      }
      // Auswertung kommt aufs (fast) selbe Ergebnis. Die Testdaten haben mehr
      // Nachkommastellen als gespeichert werden (1e-7 Grad ≈ 1 cm), das macht
      // über 7 km ein paar Meter aus. Echte u-blox-Daten haben genau diese
      // Auflösung, bei ihnen geht beim Speichern nichts verloren.
      expect(after.sessionById(id).analysis.distanceKm,
          closeTo(before.sessionById(id).analysis.distanceKm, 0.01));
    }

    // Bekannter Platz wird auch nach dem Neustart ohne OSM-Anfrage verwendet
    final fake = FakePitchService();
    final again = SessionProvider(db, pitchService: fake);
    await again.load();
    await again.addMockSession();
    await again.detectPitch(3);
    expect(again.sessionById(3).pitch!.length, 98);
    expect(fake.requests, 0);
    await db.close();
  });
}
