import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'pitch_service.dart';

/// Alle Fußballplätze Österreichs aus OpenStreetMap, als Datei in der App
/// (`assets/osm/pitches_at.json`, erzeugt von `tool/build_pitch_catalog.py`).
///
/// Damit findet die App Plätze sofort und ohne Internet. Die Overpass-Server
/// braucht sie nur noch für Plätze, die hier fehlen (im Ausland oder neu in
/// OSM eingetragen).
class PitchCatalog {
  /// Stand der Daten (JJJJ-MM-TT)
  final String date;
  final List<PitchCandidate> _pitches;
  final List<LatLng> _centers;

  PitchCatalog._(this.date, this._pitches, this._centers);

  /// Aus dem Inhalt der JSON-Datei
  factory PitchCatalog.fromJson(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    final pitches = <PitchCandidate>[];
    final centers = <LatLng>[];
    for (final entry in data['pitches'] as List<dynamic>) {
      final coords = entry[1] as List<dynamic>;
      final outline = [
        for (var i = 0; i + 1 < coords.length; i += 2)
          LatLng((coords[i] as int) / 1e6, (coords[i + 1] as int) / 1e6),
      ];
      pitches.add(PitchCandidate(outline, entry[0] as String?));
      centers.add(
        LatLng(
          outline.map((p) => p.latitude).reduce((a, b) => a + b) /
              outline.length,
          outline.map((p) => p.longitude).reduce((a, b) => a + b) /
              outline.length,
        ),
      );
    }
    return PitchCatalog._(data['date'] as String, pitches, centers);
  }

  int get length => _pitches.length;

  static const _distance = Distance();

  /// Alle Plätze, deren Mitte höchstens [radiusInMeters] entfernt ist,
  /// die nächsten zuerst. Bei ca. 10 000 Plätzen geht einfaches
  /// Durchprobieren schnell genug (wenige Millisekunden).
  List<PitchCandidate> around(LatLng center, double radiusInMeters) {
    // Grobe Vorauswahl über die Koordinaten, erst dann genau rechnen
    final dLat = radiusInMeters / 111320 + 0.002;
    final found = <(double, PitchCandidate)>[];
    for (var i = 0; i < _pitches.length; i++) {
      final c = _centers[i];
      if ((c.latitude - center.latitude).abs() > dLat) continue;
      if ((c.longitude - center.longitude).abs() > dLat * 2) continue;
      final d = _distance(center, c);
      // + 100 m: Bei großen Plätzen liegt die Mitte weiter weg als der Rand
      if (d <= radiusInMeters + 100) found.add((d, _pitches[i]));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  /// Plätze, deren Name alle Wörter aus [text] enthält (Groß-/Kleinschreibung
  /// und Umlaute egal). Mehrere Plätze derselben Anlage werden ein Treffer.
  /// Treffer nahe [near] zuerst.
  List<PlaceResult> search(String text, LatLng near, {int limit = 8}) {
    final words = _normalize(
      text,
    ).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];

    // Name → Plätze mit diesem Namen, in der Nähe zusammengefasst
    final hits = <(double, PlaceResult)>[];
    final seen = <String, List<LatLng>>{};
    for (var i = 0; i < _pitches.length; i++) {
      final name = _pitches[i].name;
      if (name == null) continue;
      final n = _normalize(name);
      if (!words.every(n.contains)) continue;
      final c = _centers[i];
      // Gleicher Name innerhalb von 1 km = dieselbe Anlage
      final same = seen[name] ??= [];
      if (same.any((s) => _distance(s, c) < 1000)) continue;
      same.add(c);
      final d = _distance(near, c);
      hits.add((d, PlaceResult(name, 'Fußballplatz · ${_km(d)}', c)));
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final h in hits.take(limit)) h.$2];
  }

  static String _km(double m) => m < 1000
      ? '${m.round()} m entfernt'
      : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0).replaceAll('.', ',')} km entfernt';

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
}
