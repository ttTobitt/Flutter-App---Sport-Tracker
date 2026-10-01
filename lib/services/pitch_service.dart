import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Lädt die Umrisse aller Fußballplätze in der Nähe aus OpenStreetMap
/// (über die Overpass-API). Welcher davon der richtige ist, entscheidet
/// `choosePitch` in `pitch_detection.dart`.
class PitchService {
  // Öffentliche Overpass-Server. Der offizielle ist oft ausgelastet, darum
  // wird zusätzlich ein zweiter gefragt.
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  // Overpass lehnt Anfragen mit dem Standard-User-Agent von Dart ab
  // (HTTP 406). Darum ein eigener, der die App erkennbar macht.
  static const _headers = {'User-Agent': 'Sporttracker-Diplomarbeit/0.1'};

  final Map<String, List<List<LatLng>>> _cache = {};

  /// Alle Fußballplätze im Umkreis von [radiusInMeters] um den Punkt.
  /// Leere Liste, wenn keiner gefunden wurde oder kein Server erreichbar ist.
  Future<List<List<LatLng>>> findPitchesAround(
    LatLng center, {
    int radiusInMeters = 300,
  }) async {
    final lat = center.latitude.toStringAsFixed(5);
    final lon = center.longitude.toStringAsFixed(5);
    final key = '$lat:$lon:$radiusInMeters';
    final cached = _cache[key];
    if (cached != null) return cached;

    final query = '''
      [out:json][timeout:20];
      way[leisure=pitch][sport=soccer](around:$radiusInMeters,$lat,$lon);
      out geom;
    ''';

    final pitches = await _firstSuccess(
      _endpoints.map((endpoint) => _query(endpoint, query)).toList(),
    );
    if (pitches == null) return const []; // kein Server erreichbar, kein Netz
    _cache[key] = pitches;
    return pitches;
  }

  /// Alle Server gleichzeitig fragen und die erste *erfolgreiche* Antwort
  /// nehmen. (Future.any reicht dafür nicht: Es nimmt die erste Antwort, die
  /// fertig wird, auch wenn sie ein Fehler ist.) null, wenn alle scheitern.
  Future<T?> _firstSuccess<T>(List<Future<T>> futures) {
    final completer = Completer<T?>();
    var failed = 0;
    for (final future in futures) {
      future.then(
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (_) {
          failed++;
          if (failed == futures.length && !completer.isCompleted) {
            completer.complete(null);
          }
        },
      );
    }
    return completer.future;
  }

  /// Fragt einen Server. Wirft eine Exception bei Fehler oder Zeitüberschreitung.
  Future<List<List<LatLng>>> _query(String endpoint, String query) async {
    final response = await http
        .post(Uri.parse(endpoint), headers: _headers, body: {'data': query})
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('$endpoint: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = decoded['elements'] as List<dynamic>? ?? const [];
    return [
      for (final element in elements)
        if (element['geometry'] case final List<dynamic> geometry
            when geometry.length >= 3)
          [
            for (final p in geometry)
              LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
          ],
    ];
  }
}
