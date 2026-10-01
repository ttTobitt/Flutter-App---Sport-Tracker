import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/session_tile.dart';

/// Verlauf: alle Einheiten, neueste zuerst, oben die Summe dieser Woche.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>().sessions;

    // Woche beginnt am Montag um 0 Uhr
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final thisWeek = sessions.where((s) => !s.start.isBefore(monday)).toList();
    final weekKm = thisWeek.fold<double>(0, (sum, s) => sum + s.analysis.distanceKm);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('VERLAUF', style: displayStyle(size: 34)),
            const SizedBox(height: 16),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Text(
                  'Noch keine Einheiten. Übertrage sie vom Tracker oder erzeuge '
                  'auf der Startseite eine Beispiel-Einheit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else ...[
              AppCard(
                child: Row(
                  children: [
                    const SectionLabel('Diese Woche'),
                    const Spacer(),
                    Text(
                      '${thisWeek.length} Einheiten · ${formatNumber(weekKm)} km',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final s in sessions) ...[
                SessionTile(session: s),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
