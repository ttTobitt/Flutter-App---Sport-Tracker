import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'pitch_catalog.dart';

/// Ein Platz aus OpenStreetMap zur Auswahl durch den Nutzer
class PitchCandidate {
  final List<LatLng> outline;

  /// Name des Platzes oder der Sportanlage, auf der er liegt. null, wenn in
  /// OpenStreetMap keiner eingetragen ist.
  final String? name;

  const PitchCandidate(this.outline, this.name);
}

/// Ein Treffer der Ortssuche (Verein, Sportanlage, Ort …)
class PlaceResult {
  final String title; // z. B. "Heinrich Hartner Sportanlage"
  final String subtitle; // Rest der Adresse
  final LatLng position;

  const PlaceResult(this.title, this.subtitle, this.position);
}

/// Kein OpenStreetMap-Server hat geantwortet (kein Netz oder überlastet)
class PitchServiceUnavailable implements Exception {
  @override
  String toString() => 'OpenStreetMap ist gerade nicht erreichbar.';
}

/// Findet Fußballplätze aus OpenStreetMap: zuerst in der Liste, die in der
/// App liegt ([PitchCatalog], Österreich, ohne Internet), sonst online über
/// die Overpass-API. Welcher Platz der richtige ist, entscheidet
/// `choosePitch` in `pitch_detection.dart`.
class PitchService {
  static const catalogAsset = 'assets/osm/pitches_at.json';

  // static: Die Liste wird nur einmal geladen, auch wenn mehrere Screens
  // einen eigenen PitchService haben
  static Future<PitchCatalog?>? _catalog;

  /// Die Platz-Liste aus der App. Wird beim ersten Gebrauch geladen (ca.
  /// 1 MB, in einem eigenen Isolate, damit die Oberfläche nicht ruckelt).
  /// null, wenn die Datei fehlt.
  Future<PitchCatalog?> catalog() => _catalog ??= () async {
    try {
      final text = await rootBundle.loadString(catalogAsset);
      return await compute(PitchCatalog.fromJson, text);
    } catch (e) {
      debugPrint('Platz-Liste nicht geladen: $e');
      return null;
    }
  }();

  /// Plätze im Umkreis aus der Liste in der App (ohne Internet)
  Future<List<List<LatLng>>> localPitchesAround(
    LatLng center, {
    int radiusInMeters = 300,
  }) async {
    final catalog = await this.catalog();
    if (catalog == null) return const [];
    return [
      for (final c in catalog.around(center, radiusInMeters.toDouble()))
        c.outline,
    ];
  }

  // Öffentliche Overpass-Server. Der offizielle ist oft ausgelastet, darum
  // wird zusätzlich ein zweiter gefragt.
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    // Französischer Server, hat die Daten der ganzen Welt. Am 18.11.2026 der
    // einzige, der geantwortet hat, als die anderen überlastet waren.
    'https://overpass.openstreetmap.fr/api/interpreter',
  ];

  // Overpass lehnt Anfragen mit dem Standard-User-Agent von Dart ab
  // (HTTP 406). Darum ein eigener, der die App erkennbar macht.
  static const _headers = {'User-Agent': 'Sporttracker-Diplomarbeit/0.1'};

  final Map<String, List<List<LatLng>>> _cache = {};

  /// Alle Fußballplätze im Umkreis von [radiusInMeters] um den Punkt, online
  /// über Overpass. Leere Liste, wenn keiner gefunden wurde oder kein Server
  /// erreichbar ist.
  Future<List<List<LatLng>>> findPitchesAround(
    LatLng center, {
    int radiusInMeters = 300,
  }) async {
    final lat = center.latitude.toStringAsFixed(5);
    final lon = center.longitude.toStringAsFixed(5);
    final key = '$lat:$lon:$radiusInMeters';
    final cached = _cache[key];
    if (cached != null) return cached;

    final query =
        '''
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

  /// Plätze im Umkreis zur Auswahl, mit Namen (eigener Name oder Name der
  /// Sportanlage, auf der der Platz liegt). Zuerst aus der Liste in der App,
  /// online nur, wenn dort keiner ist oder [online] gesetzt ist („Online
  /// nachsehen“, falls ein neuer Platz fehlt). Wirft
  /// [PitchServiceUnavailable], wenn online gefragt wird und kein Server
  /// antwortet.
  Future<List<PitchCandidate>> candidatesAround(
    LatLng center, {
    int radiusInMeters = 3000,
    bool online = false,
  }) async {
    if (!online) {
      final local = (await catalog())?.around(
        center,
        radiusInMeters.toDouble(),
      );
      if (local != null && local.isNotEmpty) return local;
    }
    final lat = center.latitude.toStringAsFixed(5);
    final lon = center.longitude.toStringAsFixed(5);
    // Plätze und benannte Sportanlagen in einer Anfrage. Plätze haben in OSM
    // oft keinen Namen, die Anlage rundherum aber schon (z. B. der Verein).
    final query =
        '''
      [out:json][timeout:25];
      (
        way[leisure=pitch][sport=soccer](around:$radiusInMeters,$lat,$lon);
        way[leisure~"^(sports_centre|stadium|recreation_ground)\$"][name](around:$radiusInMeters,$lat,$lon);
      );
      out geom;
    ''';
    final elements = await _firstSuccess(
      _endpoints.map((endpoint) => _queryElements(endpoint, query)).toList(),
    );
    if (elements == null) throw PitchServiceUnavailable();

    final pitches = <(List<LatLng>, String?)>[];
    final grounds = <(List<LatLng>, String)>[];
    for (final element in elements) {
      final tags = element['tags'] as Map<String, dynamic>? ?? const {};
      final outline = _outline(element);
      if (outline == null) continue;
      if (tags['leisure'] == 'pitch') {
        pitches.add((outline, tags['name'] as String?));
      } else {
        grounds.add((outline, tags['name'] as String));
      }
    }

    return [
      for (final (outline, name) in pitches)
        PitchCandidate(
          outline,
          name ??
              grounds
                  .where((g) => _contains(g.$1, _mean(outline)))
                  .map((g) => g.$2)
                  .firstOrNull,
        ),
    ];
  }

  /// Ortssuche über Nominatim (OpenStreetMap). Treffer in der Nähe von [near]
  /// kommen zuerst. Laut Nutzungsregeln höchstens eine Anfrage pro Sekunde und
  /// keine Suche während des Tippens: Darum wird erst beim Absenden gesucht.
  ///
  /// Zuerst wird in der Platz-Liste der App nach dem Namen gesucht (geht auch
  /// ohne Internet), danach in Nominatim (findet auch Orte und Adressen).
  Future<List<PlaceResult>> searchPlaces(String text, LatLng near) async {
    final local =
        (await catalog())?.search(text, near) ?? const <PlaceResult>[];
    try {
      final online = await _searchNominatim(text, near);
      return [...local, ...online];
    } on PitchServiceUnavailable {
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<List<PlaceResult>> _searchNominatim(String text, LatLng near) async {
    // Suchfenster ca. ±50 km um die Einheit. bounded=0: Treffer außerhalb
    // sind erlaubt, kommen aber weiter hinten.
    const d = 0.5;
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': text,
      'format': 'jsonv2',
      'limit': '8',
      'accept-language': 'de',
      'viewbox':
          '${near.longitude - d},${near.latitude + d},'
          '${near.longitude + d},${near.latitude - d}',
      'bounded': '0',
    });
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw PitchServiceUnavailable();
    }
    if (response.statusCode != 200) throw PitchServiceUnavailable();

    final results = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final r in results)
        PlaceResult(
          (r['name'] as String?)?.isNotEmpty == true
              ? r['name'] as String
              : (r['display_name'] as String).split(',').first,
          (r['display_name'] as String)
              .split(',')
              .skip(1)
              .take(3)
              .join(',')
              .trim(),
          LatLng(
            double.parse(r['lat'] as String),
            double.parse(r['lon'] as String),
          ),
        ),
    ];
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
    final elements = await _queryElements(endpoint, query);
    return elements.map(_outline).whereType<List<LatLng>>().toList();
  }

  /// Rohe Overpass-Elemente (mit Tags und Geometrie)
  Future<List<dynamic>> _queryElements(String endpoint, String query) async {
    final response = await http
        .post(Uri.parse(endpoint), headers: _headers, body: {'data': query})
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('$endpoint: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['elements'] as List<dynamic>? ?? const [];
  }

  /// Umriss eines Elements, null wenn es keine Fläche ist
  static List<LatLng>? _outline(dynamic element) {
    if (element['geometry'] case final List<dynamic> geometry
        when geometry.length >= 3) {
      return [
        for (final p in geometry)
          LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
      ];
    }
    return null;
  }

  static LatLng _mean(List<LatLng> pts) => LatLng(
    pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
    pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
  );

  /// Liegt der Punkt im Vieleck? (Strahl-Methode: Wie oft schneidet ein
  /// Strahl vom Punkt nach Osten den Rand? Ungerade = innen.)
  static bool _contains(List<LatLng> polygon, LatLng p) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }
}
