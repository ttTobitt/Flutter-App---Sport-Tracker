import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

/// Berechnet die Aufenthaltsdichte auf dem Platz (Kerndichteschätzung, KDE).
///
/// Idee: Jeder Messpunkt legt eine kleine Gauß-Glocke („Hügel“) auf ein feines
/// Raster. Wo der Spieler oft war, türmen sich die Hügel auf. So entstehen
/// weiche Übergänge statt einzelner Flecken.
///
/// Umsetzung in zwei schnellen Schritten statt „jeder Punkt × jede Zelle“:
/// 1. Punkte in Rasterzellen zählen (Histogramm)
/// 2. Das Raster mit einem Gauß-Filter weichzeichnen, erst waagrecht, dann
///    senkrecht. Das ergibt dasselbe wie die Hügel, ist aber viel schneller.
class HeatmapGrid {
  final int cols;
  final int rows;

  /// Dichte pro Zelle, normiert auf 0 … 1 (1 = Ort, an dem der Spieler am
  /// längsten war). Zeilenweise: Index = row * cols + col.
  final Float64List values;

  HeatmapGrid._(this.cols, this.rows, this.values);

  factory HeatmapGrid.compute(
    List<Offset> positions, {
    required double pitchLength,
    required double pitchWidth,
    double cellSize = 0.5, // m
    double sigma = 2.5, // m, Breite der Glocke: größer = weicher
  }) {
    final cols = (pitchLength / cellSize).ceil();
    final rows = (pitchWidth / cellSize).ceil();
    var grid = Float64List(cols * rows);

    // 1. Histogramm. Punkte außerhalb des Platzes (Bank, Aufwärmen) fallen weg.
    for (final p in positions) {
      if (p.dx < 0 || p.dy < 0 || p.dx >= pitchLength || p.dy >= pitchWidth) {
        continue;
      }
      grid[(p.dy / cellSize).floor() * cols + (p.dx / cellSize).floor()] += 1;
    }

    // 2. Gauß-Filter (separierbar)
    final kernel = _gaussKernel(sigma / cellSize);
    grid = _blur(grid, cols, rows, kernel, horizontal: true);
    grid = _blur(grid, cols, rows, kernel, horizontal: false);

    final maxValue = grid.fold<double>(0, max);
    if (maxValue > 0) {
      for (var i = 0; i < grid.length; i++) {
        grid[i] /= maxValue;
      }
    }
    return HeatmapGrid._(cols, rows, grid);
  }

  static Float64List _gaussKernel(double sigmaCells) {
    final radius = (3 * sigmaCells).ceil();
    final k = Float64List(2 * radius + 1);
    for (var i = -radius; i <= radius; i++) {
      k[i + radius] = exp(-(i * i) / (2 * sigmaCells * sigmaCells));
    }
    return k;
  }

  static Float64List _blur(
    Float64List src,
    int cols,
    int rows,
    Float64List kernel, {
    required bool horizontal,
  }) {
    final out = Float64List(src.length);
    final r = kernel.length ~/ 2;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        var sum = 0.0;
        for (var k = -r; k <= r; k++) {
          final sx = horizontal ? x + k : x;
          final sy = horizontal ? y : y + k;
          if (sx < 0 || sy < 0 || sx >= cols || sy >= rows) continue;
          sum += src[sy * cols + sx] * kernel[k + r];
        }
        out[y * cols + x] = sum;
      }
    }
    return out;
  }

  /// Farbskala: durchsichtig → Gelbgrün → Gelb → Orange → Rot.
  /// Wenig besuchte Bereiche bleiben durchsichtig, dort sieht man den Rasen.
  static const _stops = <(double, Color)>[
    (0.00, Color(0x00D9F05A)),
    (0.08, Color(0x00D9F05A)),
    (0.20, Color(0x80D9F05A)),
    (0.45, Color(0xD9FFD23F)),
    (0.70, Color(0xEBF08A24)),
    (1.00, Color(0xF5C2280C)),
  ];

  static Color colorFor(double v) {
    for (var i = 1; i < _stops.length; i++) {
      final (t1, c1) = _stops[i];
      if (v <= t1) {
        final (t0, c0) = _stops[i - 1];
        return Color.lerp(c0, c1, (v - t0) / (t1 - t0))!;
      }
    }
    return _stops.last.$2;
  }

  /// Das Raster als RGBA-Pixel (1 Pixel pro Zelle), um daraus ein Bild zu
  /// machen. Beim Zeichnen wird das Bild hochskaliert und dabei geglättet.
  ///
  /// Flutter erwartet die Farben „vormultipliziert“ (Farbe × Deckkraft).
  /// Sonst würde ein durchsichtiges Pixel trotzdem seine Farbe dazumischen.
  Uint8List toRgba() {
    final bytes = Uint8List(cols * rows * 4);
    for (var i = 0; i < values.length; i++) {
      final c = colorFor(values[i]);
      bytes[i * 4] = (c.r * c.a * 255).round();
      bytes[i * 4 + 1] = (c.g * c.a * 255).round();
      bytes[i * 4 + 2] = (c.b * c.a * 255).round();
      bytes[i * 4 + 3] = (c.a * 255).round();
    }
    return bytes;
  }
}
