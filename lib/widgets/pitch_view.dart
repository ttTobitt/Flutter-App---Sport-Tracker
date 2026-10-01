import 'dart:math';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/session_analysis.dart';
import '../theme/app_theme.dart';

enum PitchMode { heatmap, route }

/// Zeichnet ein Fußballfeld und darauf entweder die Heatmap (wo hat sich der
/// Spieler wie lange aufgehalten) oder den Laufweg (Sprints hervorgehoben).
///
/// Gezeichnet wird mit einem CustomPainter: Flutter gibt uns eine Leinwand
/// (Canvas), auf die wir Linien, Kreise und Pfade malen.
class PitchView extends StatelessWidget {
  final Session session;
  final PitchMode mode;

  const PitchView({super.key, required this.session, required this.mode});

  @override
  Widget build(BuildContext context) {
    final pitch = session.pitch;
    if (pitch == null) {
      return const AspectRatio(
        aspectRatio: 105 / 68,
        child: Center(child: Text('Kein Platz erkannt')),
      );
    }

    // GPS → Meter auf dem Platz, einmal umrechnen
    final positions = session.points
        .map((p) => pitch.toPitchMeters(p.latitude, p.longitude))
        .toList();

    return AspectRatio(
      aspectRatio: pitch.length / pitch.width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _PitchPainter(
            positions: positions,
            sprints: session.analysis.sprints,
            pitchLength: pitch.length,
            pitchWidth: pitch.width,
            mode: mode,
          ),
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  final List<Offset> positions;
  final List<Sprint> sprints;
  final double pitchLength;
  final double pitchWidth;
  final PitchMode mode;

  _PitchPainter({
    required this.positions,
    required this.sprints,
    required this.pitchLength,
    required this.pitchWidth,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.pitch);

    // Rand um das Feld, damit Punkte knapp an der Linie noch sichtbar sind
    const margin = 8.0;
    final scale = (size.width - 2 * margin) / pitchLength;
    Offset toPx(Offset m) => Offset(margin + m.dx * scale, margin + m.dy * scale);

    if (mode == PitchMode.heatmap) {
      _paintHeatmap(canvas, scale, toPx);
    }
    _paintLines(canvas, scale, toPx);
    if (mode == PitchMode.route) {
      _paintRoute(canvas, toPx);
    }
  }

  /// Heatmap: Platz in 3 × 3 m große Felder teilen, zählen, wie viele
  /// Messpunkte in jedes Feld fallen, und je Feld einen weichen Kreis malen.
  /// Je mehr Punkte, desto kräftiger die Farbe.
  void _paintHeatmap(Canvas canvas, double scale, Offset Function(Offset) toPx) {
    const cell = 3.0;
    final cols = (pitchLength / cell).ceil();
    final rows = (pitchWidth / cell).ceil();
    final counts = List.filled(cols * rows, 0);

    for (final p in positions) {
      final c = (p.dx / cell).floor().clamp(0, cols - 1);
      final r = (p.dy / cell).floor().clamp(0, rows - 1);
      counts[r * cols + c]++;
    }
    final maxCount = counts.reduce(max);
    if (maxCount == 0) return;

    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * scale);
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      // Wurzel, damit auch selten besuchte Bereiche noch sichtbar sind
      final strength = sqrt(counts[i] / maxCount);
      paint.color = AppColors.heat.withValues(alpha: 0.85 * strength);
      final center = Offset((i % cols + 0.5) * cell, (i ~/ cols + 0.5) * cell);
      canvas.drawCircle(toPx(center), cell * scale * 1.1, paint);
    }
  }

  /// Linien eines Fußballfelds nach Regelwerk (Maße in Metern)
  void _paintLines(Canvas canvas, double scale, Offset Function(Offset) toPx) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final l = pitchLength, w = pitchWidth;

    Rect rect(double x, double y, double rw, double rh) =>
        Rect.fromPoints(toPx(Offset(x, y)), toPx(Offset(x + rw, y + rh)));

    canvas.drawRect(rect(0, 0, l, w), paint); // Außenlinien
    canvas.drawLine(toPx(Offset(l / 2, 0)), toPx(Offset(l / 2, w)), paint);
    canvas.drawCircle(toPx(Offset(l / 2, w / 2)), 9.15 * scale, paint);
    // Strafräume (16,5 m tief, 40,3 m breit)
    canvas.drawRect(rect(0, (w - 40.3) / 2, 16.5, 40.3), paint);
    canvas.drawRect(rect(l - 16.5, (w - 40.3) / 2, 16.5, 40.3), paint);
    // Torräume (5,5 m tief, 18,3 m breit)
    canvas.drawRect(rect(0, (w - 18.3) / 2, 5.5, 18.3), paint);
    canvas.drawRect(rect(l - 5.5, (w - 18.3) / 2, 5.5, 18.3), paint);
  }

  /// Laufweg: der ganze Weg dünn und halbtransparent, Sprints kräftig darüber.
  void _paintRoute(Canvas canvas, Offset Function(Offset) toPx) {
    final path = Path();
    // Jeden 5. Punkt (= 1 pro Sekunde) nehmen, sonst wird es zu unruhig
    for (var i = 0; i < positions.length; i += 5) {
      final p = toPx(positions[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final sprintPaint = Paint()
      ..color = AppColors.sprint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final s in sprints) {
      final sprintPath = Path();
      for (var i = s.startIndex; i <= s.endIndex; i++) {
        final p = toPx(positions[i]);
        i == s.startIndex
            ? sprintPath.moveTo(p.dx, p.dy)
            : sprintPath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(sprintPath, sprintPaint);
    }
  }

  @override
  bool shouldRepaint(_PitchPainter old) =>
      old.mode != mode || old.positions != positions;
}
