// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sporttrackerflutterapp/main.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/services/ble_service.dart';

void main() {
  testWidgets('app starts and shows dashboard title', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SessionProvider()),
          Provider<BleService>(
            create: (_) => BleService(),
            dispose: (_, service) => service.dispose(),
          ),
        ],
        child: const SportTrackerApp(),
      ),
    );

    expect(find.text('⚡ SportTracker'), findsOneWidget);
  });
}
