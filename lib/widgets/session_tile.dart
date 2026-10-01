import 'package:flutter/material.dart';

import '../models/session.dart';
import '../screens/session_detail_screen.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Eine Zeile im Verlauf: Datum, Dauer, Sprints, Distanz. Tippen öffnet
/// die Detail-Ansicht.
class SessionTile extends StatelessWidget {
  final Session session;
  const SessionTile({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final a = session.analysis;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(session: session),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDayShort(session.start).toUpperCase(),
                      style: displayStyle(size: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatTime(session.start)} · ${minutesOf(session.duration)} min · '
                      '${a.sprints.length} Sprints',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Text(formatNumber(a.distanceKm), style: displayStyle(size: 28)),
              const SizedBox(width: 3),
              const Text('km', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
