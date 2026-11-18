import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/providers/tracker_sync.dart';
import 'package:sporttrackerflutterapp/screens/bests_screen.dart';
import 'package:sporttrackerflutterapp/screens/help_screen.dart';
import 'package:sporttrackerflutterapp/screens/history_screen.dart';
import 'package:sporttrackerflutterapp/screens/start_screen.dart';
import 'package:sporttrackerflutterapp/services/ble_service.dart';
import 'package:sporttrackerflutterapp/screens/session_detail_screen.dart';
import 'package:sporttrackerflutterapp/services/mock_session.dart';
import 'package:sporttrackerflutterapp/services/pitch_service.dart';
import 'package:sporttrackerflutterapp/services/session_database.dart';
import 'package:sporttrackerflutterapp/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePitchService extends PitchService {
  @override
  Future<List<List<LatLng>>> localPitchesAround(
    LatLng c, {
    int radiusInMeters = 300,
  }) async => [MockSessionGenerator.hartnerPolygon];
  @override
  Future<List<List<LatLng>>> findPitchesAround(
    LatLng c, {
    int radiusInMeters = 300,
  }) async => const [];
}

/// Zeichnet die Screens so schmal wie ein kleines Android-Handy
/// und mit größerer Systemschrift. Läuft etwas über („OVERFLOWED BY …“),
/// schlägt der Test fehl. So findet man solche Fehler ohne Handy.
void main() {
  sqfliteFfiInit();

  // 360 dp = übliches Android-Handy, 320 dp = kleines Handy oder
  // vergrößerte „Anzeigegröße“ in den Einstellungen
  for (final (width, textScale) in [
    (360.0, 1.0),
    (360.0, 1.3),
    (320.0, 1.0),
    (320.0, 1.3),
  ]) {
    testWidgets(
      'Kein Überlauf bei ${width.round()} dp Breite, Schrift ×$textScale',
      (tester) async {
        tester.view.physicalSize = Size(width * 3, 760 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        late SessionProvider provider;
        late Directory dir;
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('layout_test');
          final db = await SessionDatabase.open(
            factory: databaseFactoryFfi,
            path: '${dir.path}/t.db',
          );
          provider = SessionProvider(db, pitchService: _FakePitchService());
          await provider.addMockSession(); // Training
          await provider.addMockSession(); // Spiel
          await provider.detectPitch(1);
          await provider.detectPitch(2);
        });

        Future<void> show(Widget screen) async {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: provider),
                ChangeNotifierProvider.value(value: TrackerSync(provider)),
                Provider<BleService>.value(value: BleService()),
              ],
              child: MaterialApp(
                theme: buildAppTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: screen,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }

        for (final s in provider.sessions) {
          await show(SessionDetailScreen(session: s));
          // ganz nach unten scrollen, damit alles einmal gezeichnet wird
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
          );
          await tester.pump();
        }
        await show(const HistoryScreen());
        await show(const StartScreen());
        await show(const BestsScreen());
        await show(const HelpScreen());
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pump();

        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
