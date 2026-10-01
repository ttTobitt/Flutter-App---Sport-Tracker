import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sporttrackerflutterapp/models/pitch.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/pitch_service.dart';

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
  test('Platz wird erkannt, Korrektur gilt für alle Einheiten dort', () async {
    final fake = FakePitchService();
    final provider = SessionProvider(pitchService: fake);

    provider.addMockSession();
    await provider.detectPitch(1);
    expect(provider.pitchStatusOf(1), PitchStatus.found);
    expect(provider.sessionById(1).pitch!.length, closeTo(102.5, 0.5));

    // Zweite Einheit am selben Platz: kommt aus den bekannten Plätzen
    provider.addMockSession();
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
    provider.setPitch(1, corrected);
    expect(provider.sessionById(1).pitch, same(corrected));
    expect(provider.sessionById(2).pitch, same(corrected));

    // Dritte Einheit nutzt den korrigierten Platz, ohne OSM zu fragen
    final before = fake.requests;
    provider.addMockSession();
    await provider.detectPitch(3);
    expect(provider.sessionById(3).pitch, same(corrected));
    expect(fake.requests, before);
  });
}
