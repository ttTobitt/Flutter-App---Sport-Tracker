import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/session_tile.dart';
import 'ble_scan_screen.dart';

/// Startseite: Tracker-Status, Übertragung, letzte Einheit.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    final ble = context.read<BleService>();
    final latest = provider.latest;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('SPORTTRACKER', style: displayStyle(size: 34)),
            const SizedBox(height: 16),

            // ── Tracker ──────────────────────────────────────
            ValueListenableBuilder(
              valueListenable: ble.connectionStatus,
              builder: (context, status, _) {
                final connected = status == BleConnectionStatus.connected;
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Tracker'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: connected
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            connected ? 'Verbunden' : 'Nicht verbunden',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Die eigentliche Übertragung kommt mit dem
                      // BLE-Protokoll (Meilenstein 5).
                      if (!connected)
                        FilledButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BleScanScreen(),
                            ),
                          ),
                          child: const Text('Tracker verbinden'),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),

            // ── Letzte Einheit ───────────────────────────────
            if (latest != null) ...[
              const SectionLabel('Letzte Einheit'),
              const SizedBox(height: 8),
              SessionTile(session: latest),
              const SizedBox(height: 18),
            ],

            // ── Testdaten (nur für die Entwicklung) ──────────
            OutlinedButton.icon(
              onPressed: provider.addMockSession,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Beispiel-Einheit erzeugen'),
            ),
          ],
        ),
      ),
    );
  }
}
