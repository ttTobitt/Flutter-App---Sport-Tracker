import 'package:flutter_test/flutter_test.dart';
import 'package:sporttrackerflutterapp/services/heatmap.dart';

void main() {
  test('Dichte ist auf 0 … 1 normiert, Maximum am häufigsten Ort', () {
    final positions = [
      ...List.filled(50, const Offset(30, 20)),
      ...List.filled(10, const Offset(80, 50)),
    ];
    final grid = HeatmapGrid.compute(positions, pitchLength: 105, pitchWidth: 68);
    double at(double x, double y) =>
        grid.values[(y / 0.5).floor() * grid.cols + (x / 0.5).floor()];

    expect(at(30, 20), closeTo(1, 1e-9));
    expect(at(80, 50), closeTo(0.2, 0.01)); // 10 statt 50 Punkte
    expect(at(5, 60), 0); // weit weg von allen Punkten
  });

  test('Punkte außerhalb des Platzes werden ignoriert', () {
    final grid = HeatmapGrid.compute(
      [const Offset(-5, 10), const Offset(50, 80)],
      pitchLength: 105,
      pitchWidth: 68,
    );
    expect(grid.values.every((v) => v == 0), isTrue);
  });
}
