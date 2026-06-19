import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../models/sensor_data.dart';

/// Hält die aktuelle Session-Datenliste und berechnet statische Werte.
class SessionProvider extends ChangeNotifier {
  final List<SensorData> _sensorData = [];
  Timer? _mockTimer;
  bool _isMockRunning = false;
  int _mockIndex = 0;

  List<SensorData> get sensorData => List.unmodifiable(_sensorData);

  bool get hasData => _sensorData.isNotEmpty;
  bool get isMockRunning => _isMockRunning;

  SensorData? get latestData =>
      _sensorData.isEmpty ? null : _sensorData.last;

  double get currentSpeedKmh => latestData?.speedKmh ?? 0.0;

  double get averageSpeedKmh {
    if (_sensorData.isEmpty) {
      return 0.0;
    }

    final total = _sensorData.fold<double>(
      0,
      (sum, data) => sum + data.speedKmh,
    );
    return total / _sensorData.length;
  }

  double get minSpeedKmh {
    if (_sensorData.isEmpty) {
      return 0.0;
    }

    return _sensorData.map((data) => data.speedKmh).reduce(min);
  }

  double get maxSpeedKmh {
    if (_sensorData.isEmpty) {
      return 25.0;
    }

    return _sensorData.map((data) => data.speedKmh).reduce(max);
  }

  void addSensorData(SensorData data) {
    _sensorData.add(data);
    if (_sensorData.length > 500) {
      _sensorData.removeRange(0, _sensorData.length - 500);
    }
    notifyListeners();
  }

  void clearSession() {
    _sensorData.clear();
    notifyListeners();
  }

  void startMockSimulation() {
    if (_isMockRunning) {
      return;
    }

    _isMockRunning = true;
    _mockIndex = 0;
    _mockTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      final baseLat = 48.1351;
      final baseLon = 11.5820;
      final speed = 4 + (sin(_mockIndex / 2.0) + 1) * 12;
      final lat = baseLat + sin(_mockIndex / 5.0) * 0.001;
      final lon = baseLon + cos(_mockIndex / 7.0) * 0.0012;

      addSensorData(
        SensorData(
          timestamp: DateTime.now(),
          latitude: lat,
          longitude: lon,
          speedKmh: speed,
        ),
      );
      _mockIndex++;
    });

    notifyListeners();
  }

  void stopMockSimulation() {
    _isMockRunning = false;
    _mockTimer?.cancel();
    _mockTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }
}
