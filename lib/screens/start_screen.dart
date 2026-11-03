import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../providers/tracker_sync.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
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
                      if (connected) const _SyncSection(),
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

/// Übertragung der Einheiten vom Tracker: wie viele neue es gibt, Knopf
/// „Übertragen“, Fortschritt und Ergebnis
class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<TrackerSync>();
    const muted = TextStyle(color: AppColors.textMuted);

    switch (sync.state) {
      case SyncState.idle:
      case SyncState.checking:
        return const Row(
          children: [
            SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Einheiten am Tracker abfragen …', style: muted),
          ],
        );

      case SyncState.ready:
        final pending = sync.pending;
        if (pending.isEmpty) {
          return const Text('Keine neuen Einheiten am Tracker.', style: muted);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pending.length == 1
                  ? '1 neue Einheit am Tracker'
                  : '${pending.length} neue Einheiten am Tracker',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final info in pending)
              Text(
                '${formatDayTitle(info.start)}, ${formatTime(info.start)} · '
                '${_minutes(info.pointCount)} min',
                style: muted,
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: sync.transfer,
              child: const Text('Übertragen'),
            ),
          ],
        );

      case SyncState.transferring:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Einheit ${sync.current} von ${sync.total} · '
              '${(sync.progress * 100).floor()} %',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (sync.current - 1 + sync.progress) / sync.total,
              color: AppColors.pitch,
              backgroundColor: AppColors.track,
            ),
          ],
        );

      case SyncState.done:
        return Text(
          sync.transferred == 1
              ? '1 Einheit übertragen und vollständig.'
              : '${sync.transferred} Einheiten übertragen und vollständig.',
          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
        );

      case SyncState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(sync.error, style: const TextStyle(color: AppColors.danger)),
            if (sync.transferred > 0)
              Text('${sync.transferred} Einheiten wurden vorher schon übertragen.', style: muted),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: sync.retry,
              child: const Text('Nochmal versuchen'),
            ),
          ],
        );
    }
  }

  /// 5 Punkte pro Sekunde → Dauer in Minuten
  static int _minutes(int points) => (points / 5 / 60).round();
}
