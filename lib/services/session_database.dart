import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/pitch.dart';
import '../models/sensor_data.dart';
import '../models/session.dart';

/// Speichert Einheiten und Plätze lokal in SQLite, damit sie nach dem
/// Schließen der App noch da sind. Begründung des Aufbaus:
/// vault/Entscheidungen/Datenbank-Schema.md
///
/// Zwei Tabellen:
/// - `pitches`: bekannte Plätze (erkannt oder von Hand korrigiert)
/// - `sessions`: eine Zeile pro Einheit, die GPS-Punkte stecken als
///   Binärblock (BLOB) in der Spalte `points`
///
/// Kennzahlen wie Distanz oder Sprints werden nicht gespeichert, die
/// rechnet die App beim Anzeigen aus den Punkten.
class SessionDatabase {
  final Database _db;

  SessionDatabase._(this._db);

  /// Öffnet die Datenbank (legt sie beim ersten Start an). In den Tests wird
  /// [factory] auf die PC-Variante von SQLite gesetzt und [path] auf eine
  /// Datei im Temp-Ordner.
  static Future<SessionDatabase> open({DatabaseFactory? factory, String? path}) async {
    factory ??= databaseFactory;
    path ??= join(await factory.getDatabasesPath(), 'sporttracker.db');
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        // SQLite prüft Fremdschlüssel (pitch_id → pitches) nur, wenn man es
        // bei jeder Verbindung einschaltet
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
      ),
    );
    return SessionDatabase._(db);
  }

  /// Wird nur beim allerersten Öffnen aufgerufen. Ändert sich das Schema
  /// später, wird `version` erhöht und ein `onUpgrade` ergänzt, damit
  /// vorhandene Daten erhalten bleiben.
  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pitches (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        center_lat   REAL    NOT NULL,
        center_lon   REAL    NOT NULL,
        rotation_deg REAL    NOT NULL,
        length       REAL    NOT NULL,
        width        REAL    NOT NULL,
        from_osm     INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sessions (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        start    INTEGER NOT NULL,
        type     TEXT    NOT NULL,
        pitch_id INTEGER REFERENCES pitches(id) ON DELETE SET NULL,
        points   BLOB    NOT NULL
      )
    ''');
  }

  Future<void> close() => _db.close();

  /// Alle Plätze (nach ID) und alle Einheiten, neueste zuerst. Einheiten auf
  /// demselben Platz bekommen dasselbe [Pitch]-Objekt, so wie vorher im
  /// Arbeitsspeicher.
  Future<(Map<int, Pitch>, List<Session>)> loadAll() async {
    final pitches = {
      for (final row in await _db.query('pitches')) row['id'] as int: _pitchFromRow(row),
    };
    final sessions = [
      for (final row in await _db.query('sessions', orderBy: 'start DESC'))
        Session(
          id: row['id'] as int,
          points: decodePoints(
            DateTime.fromMillisecondsSinceEpoch(row['start'] as int),
            row['points'] as Uint8List,
          ),
          pitch: pitches[row['pitch_id']],
          type: SessionType.values.byName(row['type'] as String),
        ),
    ];
    return (pitches, sessions);
  }

  /// Speichert eine neu übertragene Einheit und gibt ihre ID zurück. Der Platz
  /// wird nicht mitgespeichert, weil eine neue Einheit noch keinen hat (den
  /// setzt danach [setSessionPitch]).
  Future<int> insertSession(Session session) => _db.insert('sessions', {
        'start': session.start.millisecondsSinceEpoch,
        'type': session.type.name,
        'points': encodePoints(session.points),
      });

  /// Einheit endgültig löschen. Ihr Platz bleibt gespeichert, damit er bei
  /// der nächsten Einheit dort ohne OpenStreetMap-Anfrage erkannt wird.
  Future<void> deleteSession(int sessionId) =>
      _db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);

  Future<void> setSessionType(int sessionId, SessionType type) =>
      _db.update('sessions', {'type': type.name}, where: 'id = ?', whereArgs: [sessionId]);

  Future<void> setSessionPitch(int sessionId, int? pitchId) =>
      _db.update('sessions', {'pitch_id': pitchId}, where: 'id = ?', whereArgs: [sessionId]);

  Future<int> insertPitch(Pitch pitch) => _db.insert('pitches', _pitchToRow(pitch));

  /// Platz korrigieren. Alle Einheiten, die auf diesen Platz zeigen, haben
  /// damit automatisch den neuen.
  Future<void> updatePitch(int pitchId, Pitch pitch) =>
      _db.update('pitches', _pitchToRow(pitch), where: 'id = ?', whereArgs: [pitchId]);

  static Map<String, Object?> _pitchToRow(Pitch p) => {
        'center_lat': p.centerLat,
        'center_lon': p.centerLon,
        'rotation_deg': p.rotationDeg,
        'length': p.length,
        'width': p.width,
        'from_osm': p.fromOsm ? 1 : 0,
      };

  static Pitch _pitchFromRow(Map<String, Object?> row) => Pitch(
        centerLat: row['center_lat'] as double,
        centerLon: row['center_lon'] as double,
        rotationDeg: row['rotation_deg'] as double,
        length: row['length'] as double,
        width: row['width'] as double,
        fromOsm: row['from_osm'] == 1,
      );

  // Ein Punkt im BLOB = 16 Byte, Little Endian:
  //   int32   Millisekunden seit Start der Einheit
  //   int32   Breitengrad in 1e-7 Grad (≈ 1 cm, wie u-blox es liefert)
  //   int32   Längengrad in 1e-7 Grad
  //   float32 Geschwindigkeit in km/h
  static const _bytesPerPoint = 16;
  static const _degScale = 1e7;

  static Uint8List encodePoints(List<SensorData> points) {
    final start = points.first.timestamp;
    final data = ByteData(points.length * _bytesPerPoint);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final o = i * _bytesPerPoint;
      data.setInt32(o, p.timestamp.difference(start).inMilliseconds, Endian.little);
      data.setInt32(o + 4, (p.latitude * _degScale).round(), Endian.little);
      data.setInt32(o + 8, (p.longitude * _degScale).round(), Endian.little);
      data.setFloat32(o + 12, p.speedKmh, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<SensorData> decodePoints(DateTime start, Uint8List blob) {
    final data = ByteData.sublistView(blob);
    return [
      for (var o = 0; o + _bytesPerPoint <= blob.length; o += _bytesPerPoint)
        SensorData(
          timestamp: start.add(Duration(milliseconds: data.getInt32(o, Endian.little))),
          latitude: data.getInt32(o + 4, Endian.little) / _degScale,
          longitude: data.getInt32(o + 8, Endian.little) / _degScale,
          speedKmh: data.getFloat32(o + 12, Endian.little),
        ),
    ];
  }
}
