import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Holt automatisch einen Fußballplatz in der Nähe einer GPS-Koordinate.
class PitchService {
  static const String _endpoint = 'https://overpass-api.de/api/interpreter';

  final Map<String, List<LatLng>> _cache = <String, List<LatLng>>{};

  Future<List<LatLng>> findPitchAround({
    required double latitude,
    required double longitude,
    int radiusInMeters = 500,
  }) async {
    final key = '$latitude:$longitude:$radiusInMeters';
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    final query = '''
      [out:json];
      (
        way[leisure=pitch][sport=soccer](around:$radiusInMeters,$latitude,$longitude);
        relation[leisure=pitch][sport=soccer](around:$radiusInMeters,$latitude,$longitude);
      );
      out geom;
    ''';

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        body: {'data': query},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = decoded['elements'] as List<dynamic>? ?? const [];

      for (final element in elements) {
        final geometry = element['geometry'] as List<dynamic>?;
        if (geometry == null || geometry.isEmpty) {
          continue;
        }

        final points = geometry
            .map((item) => LatLng(
                  (item['lat'] as num).toDouble(),
                  (item['lon'] as num).toDouble(),
                ))
            .toList();

        if (points.isNotEmpty) {
          _cache[key] = points;
          return points;
        }
      }
    } catch (_) {
      return const [];
    }

    return const [];
  }
}
