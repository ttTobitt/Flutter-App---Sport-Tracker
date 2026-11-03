/// Ein GPS-Messpunkt einer Einheit (vom Tracker oder aus den Testdaten).
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
}
