import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/session_provider.dart';
import '../services/session_analysis.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pitch_view.dart';
import '../widgets/speed_chart.dart';
import 'pitch_edit_screen.dart';

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
    // Immer die aktuelle Version aus dem Provider holen: Wird der Platz erst
    // nach dem Öffnen erkannt, ersetzt der Provider die Einheit.
    final provider = context.watch<SessionProvider>();
    final session = provider.sessionById(widget.session.id);
    final pitchStatus = provider.pitchStatusOf(session.id);
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
          const SizedBox(height: 14),

          // ── Training oder Spiel ──────────────────────────
          SegmentedButton<SessionType>(
            segments: const [
              ButtonSegment(value: SessionType.training, label: Text('Training')),
              ButtonSegment(value: SessionType.match, label: Text('Spiel')),
            ],
            selected: {session.type},
            showSelectedIcon: false,
            onSelectionChanged: (s) => provider.setType(session.id, s.first),
          ),
          if (session.isMatch) ...[
            const SizedBox(height: 8),
            Text(
              _halftimeText(session),
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
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
                Row(
                  children: [
                    const SectionLabel('Wo du gelaufen bist'),
                    const Spacer(),
                    // Nur bei gedrehter 2. Halbzeit ist die Richtung bekannt
                    if (session.turnsSecondHalf)
                      const Text(
                        'Angriff →',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
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
                switch (pitchStatus) {
                  PitchStatus.found => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PitchView(session: session, mode: _pitchMode),
                        Row(
                          children: [
                            // Lizenz der OSM-Daten (ODbL) verlangt diesen Hinweis
                            if (session.pitch!.fromOsm)
                              const Text(
                                'Platz: © OpenStreetMap-Mitwirkende',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => _editPitch(session.id),
                              child: const Text('Platz anpassen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  PitchStatus.searching => const _PitchPlaceholder(
                      text: 'Platz wird gesucht …',
                      busy: true,
                    ),
                  PitchStatus.notFound => _PitchPlaceholder(
                      text: 'Kein Fußballplatz gefunden.',
                      action: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => provider.detectPitch(session.id),
                            child: const Text('Nochmal suchen'),
                          ),
                          TextButton(
                            onPressed: () => _editPitch(session.id),
                            child: const Text('Von Hand festlegen'),
                          ),
                        ],
                      ),
                    ),
                },
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

  String _halftimeText(Session session) {
    final ht = session.halftime;
    if (ht == null) {
      return 'Keine Halbzeitpause gefunden. Die 2. Halbzeit wird darum nicht '
          'gedreht.';
    }
    return 'Halbzeitpause ${ht.start.inMinutes}′–${ht.end.inMinutes}′ erkannt. '
        'Die 2. Halbzeit ist gedreht, damit die Heatmap zur 1. passt.';
  }

  void _editPitch(int sessionId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PitchEditScreen(sessionId: sessionId)),
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

/// Platzhalter in Feldgröße, solange kein Platz bekannt ist
class _PitchPlaceholder extends StatelessWidget {
  final String text;
  final bool busy;
  final Widget? action;

  const _PitchPlaceholder({required this.text, this.busy = false, this.action});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 105 / 68,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.track,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
            ],
            Text(text, style: const TextStyle(color: AppColors.textMuted)),
            ?action,
          ],
        ),
      ),
    );
  }
}
