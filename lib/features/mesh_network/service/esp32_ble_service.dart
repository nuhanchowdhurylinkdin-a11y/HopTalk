import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE connection and binary data transport for the HopTalk ESP32 gateway.
class Esp32BleService {
  static const String serviceUuid = 'BE28A6AE-FE7A-4394-8858-F48BD1D62026';
  static const String rxUuid = '4AF882CE-9582-4515-BEAB-1941400E169B';
  static const String txUuid = '718CEFEA-4CE7-4A32-BC46-8C24BC97BD7E';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Uint8List> get dataStream => _dataController.stream;
  bool get isConnected => _device?.isConnected == true;
  int get mtuNow => _device?.mtuNow ?? 23;
  String? lastError;

  /// Scan for devices advertising the custom ESP32 GATT service.
  Future<List<ScanResult>> scanForDevices({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final Map<String, ScanResult> found = {};
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final hasService = result.advertisementData.serviceUuids.any(
          (uuid) => uuid.str.toUpperCase() == serviceUuid,
        );
        if (hasService) found[result.device.remoteId.str] = result;
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: timeout,
      );
      await Future<void>.delayed(timeout);
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }
    return found.values.toList();
  }

  Future<void> _connectWithRetry(BluetoothDevice device) async {
    const int maxAttempts = 5;
    for (int attempt = 1; ; attempt++) {
      try {
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 10),
          autoConnect: false,
          mtu: null,
        );
        return;
      } catch (error) {
        _log('Connect attempt $attempt/$maxAttempts failed: $error');
        try {
          await device.disconnect();
        } catch (_) {}
        if (attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<List<BluetoothService>> _discoverEspServices(
    BluetoothDevice device,
  ) async {
    List<BluetoothService> services = await device.discoverServices();
    _log('Services: ${services.map((s) => s.uuid.str).toList()}');

    bool found = services.any((s) => s.uuid.str.toUpperCase() == serviceUuid);
    if (found) return services;

    _log('ESP32 service missing, clearing GATT cache and retrying');
    try {
      await device.clearGattCache(); // শুধু Android
    } catch (error) {
      _log('clearGattCache failed: $error');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    services = await device.discoverServices();
    _log('Services after retry: ${services.map((s) => s.uuid.str).toList()}');
    return services;
  }

  Future<bool> connect(BluetoothDevice device) async {
    lastError = null;
    await disconnect();
    await FlutterBluePlus.stopScan();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    try {
      await _connectWithRetry(device);
      _device = device;

      _connectionSubscription = device.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        if (!connected) _clearCharacteristics();
        if (!_connectionController.isClosed) {
          _connectionController.add(connected);
        }
      });

      final services = await _discoverEspServices(device);
      BluetoothService? espService;
      for (final service in services) {
        if (service.uuid.str.toUpperCase() == serviceUuid) {
          espService = service;
          break;
        }
      }
      if (espService == null) {
        throw StateError('ESP32 service $serviceUuid was not found');
      }

      for (final characteristic in espService.characteristics) {
        final uuid = characteristic.uuid.str.toUpperCase();
        if (uuid == rxUuid) _rxCharacteristic = characteristic;
        if (uuid == txUuid) _txCharacteristic = characteristic;
      }
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        throw StateError('ESP32 RX/TX characteristic was not found');
      }

      try {
        await device.requestMtu(247);
      } catch (error) {
        _log('MTU request failed: $error');
      }
      _log('MTU now: ${device.mtuNow}');

      await _txCharacteristic!.setNotifyValue(true);
      _dataSubscription = _txCharacteristic!.onValueReceived.listen((bytes) {
        if (bytes.isNotEmpty && !_dataController.isClosed) {
          _dataController.add(Uint8List.fromList(bytes));
        }
      });
      if (!_connectionController.isClosed) _connectionController.add(true);
      return true;
    } catch (error) {
      lastError = error.toString();
      _log('Connect failed: $error');
      await disconnect();
      return false;
    }
  }

  /// Write one whole binary packet; the negotiated MTU must fit the packet.
  Future<bool> sendData(Uint8List bytes) async {
    final characteristic = _rxCharacteristic;
    if (characteristic == null || bytes.isEmpty) return false;

    // ATT reserves 3 bytes of each MTU for its write header.
    if (bytes.length > mtuNow - 3) {
      _log(
        'Packet ${bytes.length} bytes exceeds BLE write limit ${mtuNow - 3}',
      );
      return false;
    }
    try {
      await characteristic.write(bytes, withoutResponse: false);
      return true;
    } catch (error) {
      _log('Send failed: $error');
      return false;
    }
  }

  /// Send each user ID as its own BLE write, with no command or JSON wrapper.
  /// A begin/commit byte brackets the full snapshot so ESP32 can remove IDs
  /// that are no longer in the routing table. Each data write is one raw ID.
  Future<bool> sendUserIds(List<String> userIds) async {
    lastError = null;
    if (_rxCharacteristic == null) {
      lastError = 'ESP32 RX characteristic is not connected';
      return false;
    }

    // 0xF0 starts a replacement snapshot; 0xF1 commits it.
    if (!await sendData(Uint8List.fromList([0xF0]))) {
      lastError ??= 'Could not start the user ID snapshot';
      return false;
    }
    for (final userId in userIds) {
      final bytes = Uint8List.fromList(utf8.encode(userId));
      if (bytes.isEmpty || bytes.length > mtuNow - 3) {
        lastError = 'User ID is empty or exceeds the BLE write size';
        return false;
      }
      if (!await sendData(bytes)) {
        lastError ??= 'Failed to send a user ID to ESP32';
        return false;
      }
    }
    if (!await sendData(Uint8List.fromList([0xF1]))) {
      lastError ??= 'Could not finish the user ID snapshot';
      return false;
    }
    return true;
  }

  /// Add or remove one 16-character user ID prefix from the ESP32 route list.
  /// Wire layout: operation byte (0xA1 add, 0xA2 remove) + ID prefix bytes.
  Future<bool> sendUserIdDelta(String idPrefix, {required bool add}) async {
    lastError = null;
    if (_rxCharacteristic == null) {
      lastError = 'ESP32 RX characteristic is not connected';
      return false;
    }
    if (!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(idPrefix)) {
      lastError = 'Route ID prefix must be exactly 16 hexadecimal characters';
      return false;
    }

    final List<int> bytes = [add ? 0xA1 : 0xA2, ...utf8.encode(idPrefix)];
    if (bytes.length > mtuNow - 3) {
      lastError = 'Route ID update exceeds the BLE write size';
      return false;
    }
    return sendData(Uint8List.fromList(bytes));
  }

  /// Turn off notifications and disconnect the active ESP32.
  Future<void> disconnect() async {
    final device = _device;
    try {
      await _txCharacteristic?.setNotifyValue(false);
    } catch (_) {
      // The characteristic may already be unavailable after a link loss.
    }
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _device = null;
    _clearCharacteristics();
    if (device != null) {
      try {
        await device.disconnect();
      } catch (error) {
        _log('Disconnect failed: $error');
      }
    }
    if (!_connectionController.isClosed) _connectionController.add(false);
  }

  void _clearCharacteristics() {
    _rxCharacteristic = null;
    _txCharacteristic = null;
  }

  /// Release streams and disconnect when the owning controller is disposed.
  Future<void> dispose() async {
    await disconnect();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _connectionController.close();
    await _dataController.close();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[ESP32 BLE] $message');
  }
}
