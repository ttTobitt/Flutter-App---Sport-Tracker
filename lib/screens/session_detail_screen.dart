import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Detail-Ansicht einer einzelnen Session
/// Zeigt Statistiken, Route und Geschwindigkeitsverlauf
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session Detail')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats Grid ───────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: const [
                StatCard(value: '—', label: 'km Distanz'),
                StatCard(value: '—:—', label: 'Dauer'),
                StatCard(value: '—', label: 'km/h Max'),
                StatCard(value: '—', label: 'km/h Ø'),
              ],
            ),
            const SizedBox(height: 24),

            // ── Route Platzhalter ────────────────────────────
            const SectionLabel('Route'),
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
                    Icon(Icons.route_outlined, color: AppColors.textMuted, size: 36),
                    SizedBox(height: 8),
                    Text('Route wird hier angezeigt',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Chart Platzhalter ────────────────────────────
            const SectionLabel('Geschwindigkeitsverlauf'),
            Container(
              height: 180,
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
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
