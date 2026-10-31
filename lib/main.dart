import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/screens/history_screen.dart';
import 'package:sporttrackerflutterapp/screens/start_screen.dart';
import 'package:sporttrackerflutterapp/services/ble_service.dart';
import 'package:sporttrackerflutterapp/services/session_database.dart';
import 'package:sporttrackerflutterapp/theme/app_theme.dart';

Future<void> main() async {
  // Nötig, weil vor runApp schon auf Android (Datenbank) zugegriffen wird
  WidgetsFlutterBinding.ensureInitialized();

  // Datenbank öffnen und alle gespeicherten Einheiten laden, bevor die
  // erste Seite gezeichnet wird. So ist der Verlauf nie kurz leer.
  final db = await SessionDatabase.open();
  final sessions = SessionProvider(db);
  await sessions.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sessions),
        Provider<BleService>(
          create: (_) => BleService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: const SportTrackerApp(),
    ),
  );
}

class SportTrackerApp extends StatelessWidget {
  const SportTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportTracker',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootNav(),
    );
  }
}

/// Hält die Navigation unten zwischen Start und Verlauf.
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  final _screens = const [
    StartScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.format_list_bulleted),
            label: 'Verlauf',
          ),
        ],
      ),
    );
  }
}
