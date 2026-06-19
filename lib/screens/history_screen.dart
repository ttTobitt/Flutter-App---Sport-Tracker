import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'session_detail_screen.dart';

/// Verlauf-Seite – Liste aller vergangenen Sessions
/// Aktuell mit ein paar Platzhalter-Einträgen rein fürs Layout
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Platzhalter-Liste nur fürs Aussehen – später aus SQLite geladen
    final placeholderSessions = List.generate(3, (i) => i);

    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: placeholderSessions.isEmpty
          ? const Center(
              child: Text(
                'Noch keine Sessions gespeichert.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: placeholderSessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _SessionTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SessionDetailScreen(),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final VoidCallback onTap;
  const _SessionTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            const Text('⚽', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '19.06.2026 · 18:30',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '— km · —:— · Max — km/h',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '— km',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
