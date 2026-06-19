import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/sensor_data.dart';
import '../providers/session_provider.dart';
import '../services/pitch_service.dart';
import '../utils/speed_color.dart';

/// Zeigt die Route als farbige Polyline an und hebt optional einen Platz hervor.
class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final MapController _mapController = MapController();
  final PitchService _pitchService = PitchService();

  List<LatLng>? _pitchPoints;
  bool _isPitchLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitToRoute();
      _loadPitchIfNeeded();
    });
  }

  void _fitToRoute() {
    if (!mounted) {
      return;
    }

    final provider = context.read<SessionProvider>();
    if (provider.sensorData.length < 2) {
      return;
    }

    final points = provider.sensorData
        .map((data) => LatLng(data.latitude, data.longitude))
        .toList();

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(32),
      ),
    );
  }

  Future<void> _loadPitchIfNeeded() async {
    if (!mounted) {
      return;
    }

    final provider = context.read<SessionProvider>();
    if (provider.sensorData.length < 2 || _isPitchLoading || _pitchPoints != null) {
      return;
    }

    setState(() => _isPitchLoading = true);

    final center = provider.sensorData[provider.sensorData.length ~/ 2];
    final points = await _pitchService.findPitchAround(
      latitude: center.latitude,
      longitude: center.longitude,
      radiusInMeters: 500,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isPitchLoading = false;
      if (points.isNotEmpty) {
        _pitchPoints = points;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, provider, _) {
        final points = provider.sensorData;
        final routePoints = points
            .map((data) => LatLng(data.latitude, data.longitude))
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Speed-Route'),
          ),
          body: points.length < 2
              ? const Center(
                  child: Text('Noch keine Daten für die Route vorhanden.'),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: routePoints.first,
                    initialZoom: 13,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.sporttrackerflutterapp',
                    ),
                    if (_pitchPoints != null && _pitchPoints!.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _pitchPoints!,
                            color: Colors.green.withValues(alpha: 0.18),
                            borderColor: Colors.green.shade700,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    PolylineLayer(
                      polylines: _buildPolylines(points),
                    ),
                  ],
                ),
        );
      },
    );
  }

  List<Polyline> _buildPolylines(List<SensorData> points) {
    final speeds = points.map((p) => p.speedKmh).toList();
    final minSpeed = speeds.reduce(min);
    final maxSpeed = speeds.reduce(max);

    final safeMin = minSpeed.isFinite && minSpeed >= 0 ? minSpeed : 0.0;
    final safeMax = maxSpeed.isFinite && maxSpeed > safeMin
        ? maxSpeed
        : safeMin + 5;

    final polylines = <Polyline>[];
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final current = points[i];
      final speed = (prev.speedKmh + current.speedKmh) / 2;
      polylines.add(
        Polyline(
          points: [
            LatLng(prev.latitude, prev.longitude),
            LatLng(current.latitude, current.longitude),
          ],
          color: speedToColor(
            speed,
            minSpeed: safeMin,
            maxSpeed: safeMax,
          ),
          strokeWidth: 4,
        ),
      );
    }

    return polylines;
  }
}
