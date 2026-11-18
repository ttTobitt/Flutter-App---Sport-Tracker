import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/pitch_catalog.dart';

/// Kleine Liste im Format von tool/build_pitch_catalog.py
String _json() {
  List<int> enc(List<LatLng> outline) => [
    for (final p in outline.take(outline.length - 1)) ...[
      (p.latitude * 1e6).round(),
      (p.longitude * 1e6).round(),
    ],
  ];
  // Ein weit entfernter Platz in Graz
  const graz = [
    LatLng(47.0700, 15.4400),
    LatLng(47.0700, 15.4414),
    LatLng(47.0706, 15.4414),
    LatLng(47.0706, 15.4400),
    LatLng(47.0700, 15.4400),
  ];
  return jsonEncode({
    'source': 'Test',
    'date': '2026-11-18',
    'pitches': [
      [
        'Heinrich Hartner Sportanlage',
        enc(MockSessionGenerator.hartnerPolygon),
      ],
      [null, enc(MockSessionGenerator.neighbourPolygon)],
      ['Sportplatz Graz-Hartner', enc(graz)],
    ],
  });
}

void main() {
  final catalog = PitchCatalog.fromJson(_json());
  const pressbaum = LatLng(48.17775, 16.06832);

  test('Liste wird gelesen, Koordinaten stimmen', () {
    expect(catalog.length, 3);
    expect(catalog.date, '2026-11-18');
    final hartner = catalog.around(pressbaum, 300).first;
    expect(hartner.outline.first.latitude, closeTo(48.178011, 1e-6));
    expect(hartner.outline.length, 4); // der wiederholte Endpunkt fehlt
  });

  test('Umkreissuche: nächster zuerst, weit entfernte nicht', () {
    final near = catalog.around(pressbaum, 300);
    expect(near.length, 2);
    expect(near.first.name, 'Heinrich Hartner Sportanlage');
    expect(near[1].name, isNull);
  });

  test('Namenssuche: Groß-/Kleinschreibung egal, nahe Treffer zuerst', () {
    final hits = catalog.search('hartner', pressbaum);
    expect(hits.map((h) => h.title), [
      'Heinrich Hartner Sportanlage',
      'Sportplatz Graz-Hartner',
    ]);
    expect(
      catalog.search('Graz Hartner', pressbaum).single.title,
      'Sportplatz Graz-Hartner',
    );
    expect(catalog.search('Rapid', pressbaum), isEmpty);
  });

  test('Echte Liste aus assets/osm: Hartner-Platz drin, schnell genug', () {
    final sw = Stopwatch()..start();
    final real = PitchCatalog.fromJson(
      File('assets/osm/pitches_at.json').readAsStringSync(),
    );
    final loadMs = sw.elapsedMilliseconds;
    sw.reset();
    final near = real.around(pressbaum, 300);
    final aroundMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      '${real.length} Plätze, Stand ${real.date}: laden $loadMs ms, suchen $aroundMs ms',
    );
    expect(real.length, greaterThan(5000));
    expect(near.first.name, 'Heinrich Hartner Sportanlage');
    expect(aroundMs, lessThan(50));
  });
}
