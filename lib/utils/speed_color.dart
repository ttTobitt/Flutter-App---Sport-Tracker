import 'package:flutter/material.dart';

/// Gibt eine Farbe für die aktuelle Geschwindigkeit zurück.
Color speedToColor(
  double speed, {
  double minSpeed = 0.0,
  double maxSpeed = 25.0,
}) {
  final safeMin = minSpeed < maxSpeed ? minSpeed : 0.0;
  final safeMax = maxSpeed > safeMin ? maxSpeed : safeMin + 25;
  final clamped = speed.clamp(safeMin, safeMax);

  final ratio = safeMax == safeMin
      ? 0.5
      : (clamped - safeMin) / (safeMax - safeMin);

  final colors = <Color>[
    Colors.blue,
    Colors.lightBlueAccent,
    Colors.yellow,
    Colors.orange,
    Colors.red,
  ];

  final position = (ratio * (colors.length - 1)).clamp(0, colors.length - 1);
  final startIndex = position.floor();
  final endIndex = (startIndex + 1).clamp(0, colors.length - 1);
  final localRatio = position - startIndex;

  return Color.lerp(
    colors[startIndex],
    colors[endIndex],
    localRatio.toDouble(),
  )!;
}
