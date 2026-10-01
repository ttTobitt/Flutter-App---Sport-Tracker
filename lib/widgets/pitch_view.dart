import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/session_analysis.dart';
import '../theme/app_theme.dart';

enum PitchMode { heatmap, route }

/// Zeichnet ein Fußballfeld und darauf die Heatmap (wo hat sich der Spieler
/// wie lange aufgehalten) oder den Laufweg (Sprints hervorgehoben).
///
/// Gezeichnet wird mit einem CustomPainter: Flutter gibt uns eine Leinwand
/// (Canvas), auf die wir Linien, Flächen, Bilder und Text malen.
class PitchView extends StatefulWidget {
  final Session session;
  final PitchMode mode;

  const PitchView({super.key, required this.session, required this.mode});

  @override
  State<PitchView> createState() => _PitchViewState();
}

class _PitchViewState extends State<PitchView> {
  ui.Image? _heatmapImage;

  @override
  void initState() {
    super.initState();
    _buildHeatmapImage();
  }

  @override
  void didUpdateWidget(PitchView old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) _buildHeatmapImage();
  }

  /// Aus dem Dichte-Raster ein Bild machen (1 Pixel pro Rasterzelle).
  /// Das passiert asynchron, darum ist das Bild kurz nach dem Öffnen noch null.
  void _buildHeatmapImage() {
    final grid = widget.session.heatmap;
    if (grid == null) return;
    ui.decodeImageFromPixels(
      grid.toRgba(),
      grid.cols,
      grid.rows,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted) return;
        setState(() {
          _heatmapImage?.dispose();
          _heatmapImage = image;
        });
      },
    );
  }

  @override
  void dispose() {
    _heatmapImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final pitch = session.pitch;
    if (pitch == null) {
      return const AspectRatio(
        aspectRatio: 105 / 68,
        child: Center(child: Text('Kein Platz erkannt')),
      );
    }

    return AspectRatio(
      aspectRatio: pitch.length / pitch.width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _PitchPainter(
            session: session,
            mode: widget.mode,
            heatmapImage: _heatmapImage,
          ),
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  final Session session;
  final PitchMode mode;
  final ui.Image? heatmapImage;

  _PitchPainter({
    required this.session,
    required this.mode,
    required this.heatmapImage,
  });

  double get _length => session.pitch!.length;
  double get _width => session.pitch!.width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.pitch);

    // Rand um das Feld, damit Punkte knapp an der Linie noch sichtbar sind.
    // Maßstab so wählen, dass das Feld in beide Richtungen passt, und mittig
    // ausrichten.
    const margin = 8.0;
    final scale = min(
      (size.width - 2 * margin) / _length,
      (size.height - 2 * margin) / _width,
    );
    final origin = Offset(
      (size.width - _length * scale) / 2,
      (size.height - _width * scale) / 2,
    );
    Offset toPx(Offset m) => origin + m * scale;
    final field = Rect.fromPoints(toPx(Offset.zero), toPx(Offset(_length, _width)));

    switch (mode) {
      case PitchMode.heatmap:
        _paintHeatmap(canvas, field);
        _paintLines(canvas, scale, toPx);
      case PitchMode.route:
        _paintLines(canvas, scale, toPx);
        _paintRoute(canvas, toPx);
    }
  }

  /// Das kleine Heatmap-Bild wird auf die Feldgröße hochskaliert. Die
  /// Filterqualität sorgt dafür, dass dabei zwischen den Pixeln weich
  /// übergeblendet wird statt Kästchen zu zeigen.
  void _paintHeatmap(Canvas canvas, Rect field) {
    final image = heatmapImage;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      field,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// Linien eines Fußballfelds nach Regelwerk (Maße in Metern)
  void _paintLines(Canvas canvas, double scale, Offset Function(Offset) toPx) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final l = _length, w = _width;

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
    final positions = session.pitchPositions;
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
    for (final Sprint s in session.analysis.sprints) {
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
      old.mode != mode ||
      old.session != session ||
      old.heatmapImage != heatmapImage;
}
