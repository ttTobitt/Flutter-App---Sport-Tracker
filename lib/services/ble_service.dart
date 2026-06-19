import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/sensor_data.dart';

/// Verwaltet BLE-Scan, Verbindung und Notification-Stream.
enum BleConnectionStatus {
  disconnected,
  scanning,
  connected,
  error,
}

class BleService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _notifyCharacteristic;

  final ValueNotifier<BleConnectionStatus> connectionStatus =
      ValueNotifier(BleConnectionStatus.disconnected);
  final ValueNotifier<List<ScanResult>> scanResults =
      ValueNotifier(const <ScanResult>[]);
  final ValueNotifier<String> errorMessage = ValueNotifier('');

  Future<void> startScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      scanResults.value = const <ScanResult>[];
      connectionStatus.value = BleConnectionStatus.scanning;
      errorMessage.value = '';

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        scanResults.value = results;
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      errorMessage.value = e.toString();
      connectionStatus.value = BleConnectionStatus.error;
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    connectionStatus.value = BleConnectionStatus.disconnected;
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      errorMessage.value = '';
      _device = device;

      await device.connect(autoConnect: false);
      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          connectionStatus.value = BleConnectionStatus.connected;
        } else if (state == BluetoothConnectionState.disconnected) {
          connectionStatus.value = BleConnectionStatus.disconnected;
        }
      });

      await discoverServices();
    } catch (e) {
      errorMessage.value = e.toString();
      connectionStatus.value = BleConnectionStatus.error;
    }
  }

  Future<void> discoverServices() async {
    if (_device == null) {
      throw Exception('Kein Gerät verbunden.');
    }

    final services = await _device!.discoverServices();
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.properties.notify || characteristic.properties.indicate) {
          _notifyCharacteristic = characteristic;
          break;
        }
      }
      if (_notifyCharacteristic != null) {
        break;
      }
    }

    if (_notifyCharacteristic == null) {
      throw Exception('Keine Notify-Characteristic gefunden.');
    }
  }

  Future<void> subscribeToSensorData(
    void Function(SensorData data) onData,
  ) async {
    if (_notifyCharacteristic == null) {
      await discoverServices();
    }

    if (_notifyCharacteristic == null) {
      throw Exception('Keine Notify-Characteristic gefunden.');
    }

    _notifySubscription?.cancel();
    await _notifyCharacteristic!.setNotifyValue(true);
    _notifySubscription = _notifyCharacteristic!.lastValueStream.listen((value) {
      if (value.isEmpty) {
        return;
      }
      final sensorData = SensorData.fromBytes(value);
      onData(sensorData);
    });
  }

  Future<void> disconnect() async {
    try {
      await _notifySubscription?.cancel();
      await _device?.disconnect();
      _notifyCharacteristic = null;
      connectionStatus.value = BleConnectionStatus.disconnected;
    } catch (e) {
      errorMessage.value = e.toString();
      connectionStatus.value = BleConnectionStatus.error;
    }
  }

  void dispose() {
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_notifySubscription?.cancel());
    unawaited(FlutterBluePlus.stopScan());
    scanResults.value = const <ScanResult>[];
  }
}
