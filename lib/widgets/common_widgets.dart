import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Weiße Karte mit Rand, wie im restlichen Design
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: child,
    );
  }
}

/// Kleine Überschrift in Großbuchstaben (z. B. „GESCHWINDIGKEIT“)
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// Eine Kennzahl-Kachel: Beschriftung, große Zahl, Einheit
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color valueColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.valueColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: displayStyle(size: 44, color: valueColor)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
