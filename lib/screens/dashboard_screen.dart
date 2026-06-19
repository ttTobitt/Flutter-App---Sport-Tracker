import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import 'ble_scan_screen.dart';

/// Hauptseite mit Live-Status, Geschwindigkeit und Schnellzugriffen.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    final bleService = context.read<BleService>();

    final isCountdownActive = provider.isCountdownRunning;
    final isRunning = provider.isMockRunning && !provider.isPaused;
    final isPaused = provider.isPaused;

    final routePoints = provider.sensorData.isNotEmpty
        ? provider.sensorData
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList()
        : const [
            LatLng(48.1351, 11.5820),
            LatLng(48.1361, 11.5830),
          ];

    final mapCenter = routePoints.first;

    return Scaffold(
      appBar: AppBar(title: const Text('⚡ SportTracker')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.topRight,
              child: ValueListenableBuilder(
                valueListenable: bleService.connectionStatus,
                builder: (context, status, _) {
                  final isConnected =
                      status == BleConnectionStatus.connected;
                  return TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BleScanScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    icon: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? AppColors.success
                            : AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: const Text('BLE'),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: mapCenter,
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.sporttrackerflutterapp',
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            color: AppColors.accent,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                children: [
                  _StatLine(
                    label: 'Distanz',
                    value: '${provider.sensorData.length} km',
                  ),
                  const SizedBox(height: 8),
                  _StatLine(
                    label: 'Ø',
                    value: '${provider.averageSpeedKmh.toStringAsFixed(2)} km/h',
                  ),
                  const SizedBox(height: 8),
                  _StatLine(
                    label: 'Max',
                    value: '${provider.maxSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  if (isPaused)
                    Column(
                      children: [
                        SizedBox(
                          width: 240,
                          child: ElevatedButton.icon(
                            onPressed: provider.resumeSimulation,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('WEITER'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 240,
                          child: OutlinedButton(
                            onPressed: provider.stopMockSimulation,
                            child: const Text('Messung beenden'),
                          ),
                        ),
                      ],
                    )
                  else if (isRunning)
                    Column(
                      children: [
                        SizedBox(
                          width: 240,
                          child: ElevatedButton(
                            onPressed: provider.requestPause,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('PAUSE'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 240,
                          child: OutlinedButton(
                            onPressed: provider.stopMockSimulation,
                            child: const Text('STOPP'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Messung läuft',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        SizedBox(
                          width: 240,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (isCountdownActive) {
                                provider.cancelCountdown();
                                provider.startMockSimulation();
                              } else {
                                provider.startCountdown();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: Icon(
                              isCountdownActive
                                  ? Icons.timer
                                  : Icons.play_arrow,
                            ),
                            label: Text(
                              isCountdownActive
                                  ? 'START in ${provider.countdownSeconds}s'
                                  : 'START',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (isCountdownActive)
                          const Text(
                            'Erneuter Druck startet sofort',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;

  const _StatLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
