import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sensor_data.dart';
import '../providers/session_provider.dart';
import '../services/ble_service.dart';

/// Screen zum Suchen und Verbinden von BLE-Geräten.
class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  late final BleService _bleService;

  @override
  void initState() {
    super.initState();
    _bleService = context.read<BleService>();
    _bleService.startScan();
  }

  @override
  void dispose() {
    _bleService.stopScan();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE-Geräte'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _bleService.connectionStatus,
          _bleService.scanResults,
          _bleService.errorMessage,
        ]),
        builder: (context, _) {
          final status = _bleService.connectionStatus.value;
          final results = _bleService.scanResults.value;
          final error = _bleService.errorMessage.value;

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusText(status),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (error.isNotEmpty)
                  Text(
                    error,
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: results.isEmpty
                      ? const Center(
                          child: Text('Noch keine Geräte gefunden.'),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final result = results[index];
                            final device = result.device;
                            return ListTile(
                              title: Text(device.platformName.isNotEmpty
                                  ? device.platformName
                                  : 'Unbekanntes Gerät'),
                              subtitle: Text(device.remoteId.str),
                              trailing: Text(result.rssi.toString()),
                              onTap: () async {
                                final provider = context.read<SessionProvider>();
                                if (!mounted) return;

                                await _bleService.connect(device);
                                if (!mounted) return;

                                provider.addSensorData(
                                  SensorData(
                                    timestamp: DateTime.now(),
                                    latitude: 48.1351,
                                    longitude: 11.5820,
                                    speedKmh: provider.currentSpeedKmh,
                                  ),
                                );
                                if (_bleService.connectionStatus.value ==
                                    BleConnectionStatus.connected) {
                                  await _bleService.subscribeToSensorData(
                                    (sensorData) {
                                      provider.addSensorData(sensorData);
                                    },
                                  );
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusText(BleConnectionStatus status) {
    return switch (status) {
      BleConnectionStatus.scanning => 'Scannen…',
      BleConnectionStatus.connected => 'Verbunden',
      BleConnectionStatus.error => 'Fehler',
      BleConnectionStatus.disconnected => 'Getrennt',
    };
  }
}
