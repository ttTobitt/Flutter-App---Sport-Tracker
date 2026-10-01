import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/session_analysis.dart';
import '../theme/app_theme.dart';

/// Geschwindigkeit über die Zeit, Sprints als Punkte markiert,
/// gestrichelte Linie bei der Sprint-Schwelle.
///
/// Selbst gezeichnet statt mit einer Chart-Library (z. B. fl_chart): Wir
/// brauchen nur eine Linie, und so passt es genau zum restlichen Design.
class SpeedChart extends StatelessWidget {
  final Session session;
  final double height;

  const SpeedChart({super.key, required this.session, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SpeedChartPainter(session)),
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  final Session session;
  _SpeedChartPainter(this.session);

  @override
  void paint(Canvas canvas, Size size) {
    final points = session.points;
    if (points.length < 2) return;

    final analysis = session.analysis;
    final maxY = max(30.0, analysis.maxSpeedKmh);
    double y(double kmh) => size.height - kmh / maxY * size.height;
    double xOfIndex(int i) => i / (points.length - 1) * size.width;

    // Halbzeitpause bei Spielen grau hinterlegen
    final ht = session.halftime;
    if (session.isMatch && ht != null) {
      canvas.drawRect(
        Rect.fromLTRB(xOfIndex(ht.startIndex), 0, xOfIndex(ht.endIndex), size.height),
        Paint()..color = AppColors.track,
      );
    }

    // Bei 5 Hz hat eine Einheit über 25.000 Punkte, der Bildschirm aber nur
    // ein paar hundert Pixel. Darum Punkte in Gruppen zusammenfassen
    // (Mittelwert pro 2 Pixel), so bleibt die Kurve ruhig und schnell.
    final buckets = max(2, (size.width / 2).floor());
    final perBucket = points.length / buckets;
    final path = Path();
    for (var b = 0; b < buckets; b++) {
      final from = (b * perBucket).floor();
      final to = min(points.length, ((b + 1) * perBucket).floor());
      if (to <= from) continue;
      var sum = 0.0;
      for (var i = from; i < to; i++) {
        sum += points[i].speedKmh;
      }
      final px = Offset(b / (buckets - 1) * size.width, y(sum / (to - from)));
      b == 0 ? path.moveTo(px.dx, px.dy) : path.lineTo(px.dx, px.dy);
    }

    // Grundlinie
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = AppColors.track,
    );

    // Sprint-Schwelle gestrichelt
    final thresholdY = y(SessionAnalysis.sprintThresholdKmh);
    final dashPaint = Paint()
      ..color = AppColors.sprint
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, thresholdY), Offset(x + 4, thresholdY), dashPaint);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = ui.StrokeJoin.round,
    );

    // Sprints als Punkte an ihrer Spitzengeschwindigkeit
    final dot = Paint()..color = AppColors.sprint;
    for (final s in analysis.sprints) {
      canvas.drawCircle(Offset(xOfIndex(s.peakIndex), y(s.maxSpeedKmh)), 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) => old.session != session;
}
