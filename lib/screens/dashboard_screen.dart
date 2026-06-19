import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Hauptseite – zeigt BLE-Status, Live-Stats, Karte und Speed-Chart
/// Aktuell nur das optische Grundgerüst, ohne echte Logik/Daten
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚡ SportTracker')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── BLE Status Bar ──────────────────────────────
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Nicht verbunden',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Verbinden'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Stats Grid ───────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: const [
                StatCard(value: '0.0', label: 'km/h'),
                StatCard(value: '0.00', label: 'km Distanz'),
                StatCard(value: '00:00', label: 'Dauer'),
                StatCard(value: '0.0', label: 'km/h Max'),
              ],
            ),
            const SizedBox(height: 24),

            // ── Karte Platzhalter ────────────────────────────
            const SectionLabel('Live Karte'),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, color: AppColors.textMuted, size: 36),
                    SizedBox(height: 8),
                    Text('Karte wird hier angezeigt',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Chart Platzhalter ────────────────────────────
            const SectionLabel('Geschwindigkeit'),
            Container(
              height: 180,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.show_chart, color: AppColors.textMuted, size: 32),
                    SizedBox(height: 8),
                    Text('Chart wird hier angezeigt',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Session Controls ─────────────────────────────
            Center(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow),
                label: const Text('Session starten'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(220, 52),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
