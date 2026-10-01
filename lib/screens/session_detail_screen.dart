import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/session_analysis.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pitch_view.dart';
import '../widgets/speed_chart.dart';

/// Detail-Ansicht einer Einheit: Kennzahlen, Heatmap/Laufweg,
/// Geschwindigkeitsverlauf und Zeit pro Geschwindigkeitszone.
class SessionDetailScreen extends StatefulWidget {
  final Session session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  PitchMode _pitchMode = PitchMode.heatmap;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final a = session.analysis;

    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          // ── Titel ────────────────────────────────────────
          Text(
            formatDayTitle(session.start).toUpperCase(),
            style: displayStyle(size: 34),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatTime(session.start)} – ${formatTime(session.end)}',
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),

          // ── Kennzahlen ───────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                label: 'Distanz',
                value: formatNumber(a.distanceKm),
                unit: 'km',
              ),
              StatCard(
                label: 'Sprints',
                value: '${a.sprints.length}',
                valueColor: AppColors.sprint,
              ),
              StatCard(
                label: 'Max',
                value: formatNumber(a.maxSpeedKmh),
                unit: 'km/h',
              ),
              StatCard(
                label: 'Dauer',
                value: '${minutesOf(session.duration)}',
                unit: 'min',
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Heatmap / Laufweg ────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Wo du gelaufen bist'),
                const SizedBox(height: 12),
                SegmentedButton<PitchMode>(
                  segments: const [
                    ButtonSegment(value: PitchMode.heatmap, label: Text('Heatmap')),
                    ButtonSegment(value: PitchMode.route, label: Text('Laufweg')),
                  ],
                  selected: {_pitchMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _pitchMode = s.first),
                ),
                const SizedBox(height: 12),
                PitchView(session: session, mode: _pitchMode),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Geschwindigkeitsverlauf ─────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SectionLabel('Geschwindigkeit'),
                    const Spacer(),
                    Text(
                      'Ø ${formatNumber(a.avgSpeedKmh)} km/h',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SpeedChart(session: session),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("0′", style: _axisStyle),
                    const Spacer(),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.sprint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sprint ab ${SessionAnalysis.sprintThresholdKmh.round()} km/h',
                      style: _axisStyle,
                    ),
                    const Spacer(),
                    Text("${minutesOf(session.duration)}′", style: _axisStyle),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Zeit pro Zone ────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Zeit pro Zone'),
                const SizedBox(height: 12),
                for (var i = 0; i < SessionAnalysis.zones.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ZoneRow(
                      zone: SessionAnalysis.zones[i],
                      share: a.zoneShares[i],
                      color: AppColors.zones[i],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _axisStyle = TextStyle(fontSize: 12, color: AppColors.textMuted);
}

class _ZoneRow extends StatelessWidget {
  final SpeedZone zone;
  final double share;
  final Color color;

  const _ZoneRow({required this.zone, required this.share, required this.color});

  String get _range => zone.toKmh.isInfinite
      ? '> ${zone.fromKmh.round()} km/h'
      : zone.fromKmh == 0
          ? '< ${zone.toKmh.round()} km/h'
          : '${zone.fromKmh.round()}–${zone.toKmh.round()} km/h';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(zone.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(_range,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 10,
              color: color,
              backgroundColor: AppColors.track,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${(share * 100).round()} %',
            textAlign: TextAlign.right,
            style: displayStyle(size: 18),
          ),
        ),
      ],
    );
  }
}
