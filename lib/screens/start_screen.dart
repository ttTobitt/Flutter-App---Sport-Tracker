import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../providers/tracker_sync.dart';
import '../services/ble_service.dart';
import '../services/stats.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/session_tile.dart';
import 'ble_scan_screen.dart';
import 'bests_screen.dart';
import 'help_screen.dart';

/// Startseite: Tracker (Status, Akku, Übertragung), diese Woche, letzte
/// Einheit, Bestwerte. Oben rechts die Hilfe.
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
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('SPORTTRACKER', style: displayStyle(size: 34)),
                  ),
                ),
                IconButton(
                  tooltip: 'Hilfe',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HelpScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

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
                          const Spacer(),
                          if (connected) _BatteryLevel(ble.batteryPercent),
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

            // ── Diese Woche ──────────────────────────────────
            _WeekCard(WeekSummary.of(provider.sessions, DateTime.now())),
            const SizedBox(height: 18),

            // ── Letzte Einheit ───────────────────────────────
            if (latest != null) ...[
              const SectionLabel('Letzte Einheit'),
              const SizedBox(height: 8),
              SessionTile(session: latest),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BestsScreen()),
                ),
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Bestwerte'),
              ),
            ],
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
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
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
          style: const TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        );

      case SyncState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(sync.error, style: const TextStyle(color: AppColors.danger)),
            if (sync.transferred > 0)
              Text(
                '${sync.transferred} Einheiten wurden vorher schon übertragen.',
                style: muted,
              ),
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

/// Akku des Trackers, z. B. „78 %“ mit passendem Symbol
class _BatteryLevel extends StatelessWidget {
  final ValueNotifier<int?> percent;
  const _BatteryLevel(this.percent);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: percent,
      builder: (context, p, _) {
        if (p == null) return const SizedBox.shrink(); // ältere Firmware
        final low = p <= 20;
        final icon = p >= 90
            ? Icons.battery_full
            : p >= 60
            ? Icons.battery_5_bar
            : p >= 35
            ? Icons.battery_3_bar
            : p > 20
            ? Icons.battery_2_bar
            : Icons.battery_alert;
        final color = low ? AppColors.danger : AppColors.textMuted;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 2),
            Text(
              '$p %',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: low ? color : AppColors.ink,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Diese Woche: Einheiten, Kilometer, Sprints und ein Balken pro Tag
class _WeekCard extends StatelessWidget {
  final WeekSummary week;
  const _WeekCard(this.week);

  static const _days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1;
    final maxKm = week.kmPerDay.reduce((a, b) => a > b ? a : b);

    Widget number(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: displayStyle(size: 32)),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Diese Woche'),
          const SizedBox(height: 8),
          Row(
            children: [
              number(
                '${week.sessions}',
                week.sessions == 1 ? 'Einheit' : 'Einheiten',
              ),
              number(formatNumber(week.km), 'km'),
              number('${week.sprints}', 'Sprints'),
            ],
          ),
          const SizedBox(height: 14),
          // Ein Balken pro Tag, Höhe = Kilometer. Tage ohne Einheit als
          // flacher Strich, damit man die Woche trotzdem erkennt.
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          // Der Balken bekommt, was neben der Beschriftung
                          // übrig bleibt (bei großer Schrift weniger)
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: maxKm == 0
                                    ? 0.06
                                    : 0.06 + 0.94 * week.kmPerDay[d] / maxKm,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: week.kmPerDay[d] > 0
                                        ? AppColors.pitch
                                        : AppColors.track,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _days[d],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: d == today
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: d == today
                                  ? AppColors.ink
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
