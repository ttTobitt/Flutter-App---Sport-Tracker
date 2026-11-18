import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'tracker_client.dart';

/// Verwaltet BLE-Scan und Verbindung. Nach dem Verbinden steht über [link]
/// die Leitung zum Tracker bereit, über die `TrackerClient` die Befehle
/// aus vault/BLE-Protokoll.md schickt.
enum BleConnectionStatus { disconnected, scanning, connected, error }

/// UUIDs des Sporttrackers. Müssen mit der Firmware übereinstimmen,
/// siehe vault/BLE-Protokoll.md.
class TrackerUuids {
  static final service = Guid('be440001-a3df-4184-b0be-9ee4a9662653');
  static final commands = Guid('be440002-a3df-4184-b0be-9ee4a9662653');
  static final data = Guid('be440003-a3df-4184-b0be-9ee4a9662653');

  // Standard-Akku-Dienst von Bluetooth (von der Bluetooth SIG vergeben)
  static final batteryService = Guid('180F');
  static final batteryLevel = Guid('2A19');
}

class BleService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  BluetoothDevice? _device;
  TrackerLink? _link;

  /// Leitung zum Tracker, null solange keiner verbunden ist
  TrackerLink? get link => _link;

  final ValueNotifier<BleConnectionStatus> connectionStatus = ValueNotifier(
    BleConnectionStatus.disconnected,
  );
  final ValueNotifier<List<ScanResult>> scanResults = ValueNotifier(
    const <ScanResult>[],
  );
  final ValueNotifier<String> errorMessage = ValueNotifier('');

  /// Akkustand des Trackers in %, null wenn nicht verbunden oder die
  /// Firmware ihn (noch) nicht sendet
  final ValueNotifier<int?> batteryPercent = ValueNotifier(null);
  StreamSubscription<List<int>>? _batterySubscription;

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

      // Nur Geräte anzeigen, die unseren Service im Advertising mitsenden.
      // Kopfhörer, Uhren usw. werden so schon von Android herausgefiltert.
      await FlutterBluePlus.startScan(
        withServices: [TrackerUuids.service],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      // Android ≤ 11 sucht nur mit eingeschaltetem Standort nach BLE-Geräten
      errorMessage.value = e.toString().contains('Location services')
          ? 'Bitte Standort am Handy einschalten – Android braucht ihn für die Bluetooth-Suche.'
          : e.toString();
      connectionStatus.value = BleConnectionStatus.error;
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    // Nur zurücksetzen, wenn noch gesucht wurde. Ist inzwischen ein Tracker
    // verbunden (Suche wird beim Schließen der Seite gestoppt), bleibt das so.
    if (connectionStatus.value == BleConnectionStatus.scanning) {
      connectionStatus.value = BleConnectionStatus.disconnected;
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      errorMessage.value = '';
      _device = device;
      // Android verbindet zuverlässiger, wenn nicht gleichzeitig gesucht wird
      await FlutterBluePlus.stopScan();

      // flutter_blue_plus fragt auf Android dabei automatisch eine große MTU
      // an (512). Der Tracker kann 247, ausgehandelt wird das kleinere.
      await device.connect(autoConnect: false);
      _link = await _findTracker(device);
      await _watchBattery(device);

      // Erst jetzt „verbunden“ melden: Wer darauf reagiert (TrackerSync),
      // kann dann sofort Befehle schicken.
      connectionStatus.value = BleConnectionStatus.connected;

      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _link = null;
          batteryPercent.value = null;
          connectionStatus.value = BleConnectionStatus.disconnected;
        }
      });
    } catch (e) {
      _link = null;
      errorMessage.value = e.toString();
      connectionStatus.value = BleConnectionStatus.error;
      // Halb aufgebaute Verbindung wieder trennen, Fehler dabei egal
      await device.disconnect().catchError((_) {});
    }
  }

  /// Service und die beiden Characteristics über ihre UUIDs suchen und die
  /// Notifications der Daten-Characteristic einschalten
  Future<TrackerLink> _findTracker(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = services
        .where((s) => s.uuid == TrackerUuids.service)
        .firstOrNull;
    if (service == null) {
      throw Exception('Das Gerät ist kein Sporttracker (Service fehlt).');
    }
    BluetoothCharacteristic find(Guid uuid) {
      final c = service.characteristics
          .where((c) => c.uuid == uuid)
          .firstOrNull;
      if (c == null) throw Exception('Characteristic $uuid fehlt am Tracker.');
      return c;
    }

    final commands = find(TrackerUuids.commands);
    final data = find(TrackerUuids.data);
    // Muss vor dem ersten Befehl passieren, sonst bricht der Tracker die
    // Übertragung ab (er sendet nur, wenn jemand zuhört)
    await data.setNotifyValue(true);
    return _BleTrackerLink(commands, data);
  }

  /// Akkustand einmal lesen und Änderungen abonnieren. Fehlt der Dienst
  /// (ältere Firmware) oder klappt etwas nicht, bleibt er einfach leer: Der
  /// Akku ist nur eine Anzeige, die Übertragung geht trotzdem.
  Future<void> _watchBattery(BluetoothDevice device) async {
    await _batterySubscription?.cancel();
    batteryPercent.value = null;
    try {
      // discoverServices() wurde in _findTracker schon aufgerufen
      final level = device.servicesList
          .where((s) => s.uuid == TrackerUuids.batteryService)
          .expand((s) => s.characteristics)
          .where((c) => c.uuid == TrackerUuids.batteryLevel)
          .firstOrNull;
      if (level == null) return;
      _batterySubscription = level.onValueReceived.listen((v) {
        if (v.isNotEmpty) batteryPercent.value = v.first;
      });
      device.cancelWhenDisconnected(_batterySubscription!);
      final value = await level.read();
      if (value.isNotEmpty) batteryPercent.value = value.first;
      await level.setNotifyValue(true);
    } catch (e) {
      debugPrint('Akkustand nicht lesbar: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
      _link = null;
      batteryPercent.value = null;
      connectionStatus.value = BleConnectionStatus.disconnected;
    } catch (e) {
      errorMessage.value = e.toString();
      connectionStatus.value = BleConnectionStatus.error;
    }
  }

  void dispose() {
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(FlutterBluePlus.stopScan());
    scanResults.value = const <ScanResult>[];
  }
}

/// [TrackerLink] über Bluetooth: Befehle auf die Befehls-Characteristic
/// schreiben, Notifications der Daten-Characteristic weiterreichen
class _BleTrackerLink implements TrackerLink {
  final BluetoothCharacteristic _commands;
  final BluetoothCharacteristic _data;

  _BleTrackerLink(this._commands, this._data);

  // onValueReceived liefert nur echte Notifications (lastValueStream würde
  // auch den zuletzt bekannten Wert wiederholen)
  @override
  Stream<List<int>> get notifications => _data.onValueReceived;

  // Mit Antwort schreiben: Die Firmware erlaubt nur „Write“, nicht „Write
  // without response“
  @override
  Future<void> write(List<int> command) => _commands.write(command);
}
