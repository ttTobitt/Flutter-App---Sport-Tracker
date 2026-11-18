import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/stats.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'session_detail_screen.dart';

/// Bestwerte über alle Einheiten. Antippen öffnet die Einheit dazu.
class BestsScreen extends StatelessWidget {
  const BestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bests = Bests.of(context.watch<SessionProvider>().sessions);

    return Scaffold(
      appBar: AppBar(title: const Text('Bestwerte')),
      body: bests == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Noch keine Einheiten. Bestwerte gibt es nach dem ersten Training.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _BestCard(
                  label: 'Höchstgeschwindigkeit',
                  best: bests.maxSpeed,
                  value: formatNumber(bests.maxSpeed.value),
                  unit: 'km/h',
                  color: AppColors.sprint,
                ),
                _BestCard(
                  label: 'Längste Distanz',
                  best: bests.distance,
                  value: formatNumber(bests.distance.value),
                  unit: 'km',
                ),
                _BestCard(
                  label: 'Meiste Sprints',
                  best: bests.sprints,
                  value: '${bests.sprints.value.round()}',
                  unit: 'Sprints',
                  color: AppColors.sprint,
                ),
                _BestCard(
                  label: 'Längste Einheit',
                  best: bests.duration,
                  value: '${bests.duration.value.floor()}',
                  unit: 'min',
                ),
              ],
            ),
    );
  }
}

class _BestCard extends StatelessWidget {
  final String label;
  final Best best;
  final String value;
  final String unit;
  final Color color;

  const _BestCard({
    required this.label,
    required this.best,
    required this.value,
    required this.unit,
    this.color = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    final s = best.session;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SessionDetailScreen(session: s)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(label),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              value,
                              style: displayStyle(size: 40, color: color),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              unit,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${s.isMatch ? 'Spiel' : 'Training'} · '
                        '${formatDayTitle(s.start)} · ${formatTime(s.start)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
