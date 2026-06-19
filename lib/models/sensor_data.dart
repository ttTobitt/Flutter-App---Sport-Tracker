import 'dart:convert';

/// Ein einzelner GPS-/Sensor-Datensatz, der aus BLE oder Simulation stammt.
class SensorData {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speedKmh;

  const SensorData({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
  });

  /// Geschwindigkeit in m/s.
  double get speedMps => speedKmh / 3.6;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'speedKmh': speedKmh,
    };
  }

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Erlaubt einfache BLE-Daten wie:
  /// "48.1351,11.5820,12.3"
  factory SensorData.fromBytes(List<int> bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true).trim();
    final parts = raw.split(RegExp(r'[,;\s]+'));

    if (parts.length >= 3) {
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      final speed = double.tryParse(parts[2]);

      if (lat != null && lon != null && speed != null) {
        return SensorData(
          timestamp: DateTime.now(),
          latitude: lat,
          longitude: lon,
          speedKmh: speed,
        );
      }
    }

    return SensorData(
      timestamp: DateTime.now(),
      latitude: 0,
      longitude: 0,
      speedKmh: 0,
    );
  }
}
