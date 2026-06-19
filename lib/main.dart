import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sporttrackerflutterapp/providers/session_provider.dart';
import 'package:sporttrackerflutterapp/screens/dashboard_screen.dart';
import 'package:sporttrackerflutterapp/screens/history_screen.dart';
import 'package:sporttrackerflutterapp/services/ble_service.dart';
import 'package:sporttrackerflutterapp/theme/app_theme.dart';

void main() {
  runApp(
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

/// Hält die Bottom-Navigation zwischen Dashboard und Verlauf.
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Verlauf',
          ),
        ],
      ),
    );
  }
}
