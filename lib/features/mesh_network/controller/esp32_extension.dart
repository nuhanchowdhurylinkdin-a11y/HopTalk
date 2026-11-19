part of 'mesh_network_controller.dart';

extension MeshEsp32 on MeshNetworkController {
  void setEsp32Connected(bool value) {
    if (isEsp32Connected.value == value) return;
    isEsp32Connected.value = value;
    _log("ESP32 connected: $value");

    if (value) {
      unawaited(_sendInitialEsp32UserIds());
    } else {
      _esp32InitialUserIdSyncComplete = false;
      _pendingEsp32UserIdDeltas.clear();
    }

    final RouteEntry? self = routingTable[_currentUserId];
    if (self != null) {
      routingTable[_currentUserId] = RouteEntry(
        destinationId: self.destinationId,
        nextHopId: 'SELF',
        hopCount: 0,
        avatar: self.avatar,
        imageByte: self.imageByte,
        hasEsp32: value,
      );
      _broadcastRoutingTable();
    }
    update();
  }

  /// Scan for ESP32 boards advertising the configured custom BLE service.

  Future<List<ScanResult>> scanEsp32Devices() async {
    if (isEsp32Scanning.value) return const [];
    isEsp32Scanning.value = true;
    update();
    try {
      return await _esp32Ble.scanForDevices();
    } catch (error) {
      _log('ESP32 scan failed: $error');
      return const [];
    } finally {
      isEsp32Scanning.value = false;
      update();
    }
  }

  /// Connect the selected ESP32 and mark this phone as a LoRa gateway.

  Future<bool> connectEsp32(BluetoothDevice device) async {
    final connected = await _esp32Ble.connect(device);
    if (!connected) return false;
    setEsp32Connected(true);
    esp32UserIdSyncError = null;
    await _sendInitialEsp32UserIds();
    return true;
  }

  /// Send one full prefix list when ESP32 connects, then send only route deltas.

  Future<void> _sendInitialEsp32UserIds() {
    if (!isEsp32Connected.value) return Future<void>.value();
    final activeTask = _esp32InitialUserIdSyncTask;
    if (activeTask != null) return activeTask;

    final completer = Completer<void>();
    _esp32InitialUserIdSyncTask = completer.future;
    () async {
      try {
        _esp32InitialUserIdSyncComplete = false;
        final Map<String, String> fullIdByPrefix = {};
        for (final fullId in routingTable.keys) {
          final prefix = _loraIdPrefix(fullId);
          final otherId = fullIdByPrefix[prefix];
          if (otherId != null && otherId != fullId) {
            esp32UserIdSyncError = 'Two routing IDs share prefix $prefix';
            _log('Cannot sync ambiguous user ID prefix: $prefix');
            return;
          }
          fullIdByPrefix[prefix] = fullId;
        }
        final prefixes = fullIdByPrefix.keys.toList()..sort();
        if (!await _esp32Ble.sendUserIds(prefixes)) {
          esp32UserIdSyncError = _esp32Ble.lastError;
          _log('ESP32 initial user ID sync failed: $esp32UserIdSyncError');
          return;
        }

        esp32UserIdSyncError = null;
        _esp32InitialUserIdSyncComplete = true;
        _log('Sent initial list of ${prefixes.length} user ID prefixes');
        await _drainEsp32UserIdDeltas();
      } finally {
        _esp32InitialUserIdSyncTask = null;
        completer.complete();
      }
    }();
    return completer.future;
  }

  /// Queue a single user add/remove while the initial snapshot or another delta is sending.

  void _queueEsp32UserIdDelta(String fullId, {required bool add}) {
    if (!isEsp32Connected.value) return;
    final String prefix;
    try {
      prefix = _loraIdPrefix(fullId);
      final bool samePrefixStillPresent = routingTable.keys.any(
        (otherId) => otherId != fullId && _loraIdPrefix(otherId) == prefix,
      );
      if (add && samePrefixStillPresent) {
        esp32UserIdSyncError = 'Two routing IDs share prefix $prefix';
        _log('Cannot add ambiguous user ID prefix: $prefix');
        return;
      }
      // If another full ID still maps to this prefix, retain the ESP32 entry.
      if (!add && samePrefixStillPresent) return;
    } on FormatException catch (error) {
      esp32UserIdSyncError = error.message;
      _log('Cannot sync route ID: ${error.message}');
      return;
    }

    _pendingEsp32UserIdDeltas.add((prefix, add));
    if (_esp32InitialUserIdSyncComplete) {
      unawaited(_drainEsp32UserIdDeltas());
    }
  }

  /// Serialize queued add/remove writes so rapid mesh changes stay in order.

  Future<void> _drainEsp32UserIdDeltas() {
    if (!isEsp32Connected.value || !_esp32InitialUserIdSyncComplete) {
      return Future<void>.value();
    }
    final activeTask = _esp32UserIdDeltaTask;
    if (activeTask != null) return activeTask;

    final completer = Completer<void>();
    _esp32UserIdDeltaTask = completer.future;
    () async {
      try {
        while (_pendingEsp32UserIdDeltas.isNotEmpty && isEsp32Connected.value) {
          final (prefix, add) = _pendingEsp32UserIdDeltas.first;
          if (!await _esp32Ble.sendUserIdDelta(prefix, add: add)) {
            esp32UserIdSyncError = _esp32Ble.lastError;
            _log('ESP32 user ID delta failed: $esp32UserIdSyncError');
            break;
          }
          _pendingEsp32UserIdDeltas.removeAt(0);
          esp32UserIdSyncError = null;
          _log('${add ? 'Added' : 'Removed'} user ID prefix $prefix on ESP32');
        }
      } finally {
        _esp32UserIdDeltaTask = null;
        completer.complete();
      }
    }();
    return completer.future;
  }

  String _loraIdPrefix(String fullId) {
    if (fullId.length < 16 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(fullId)) {
      throw FormatException('Invalid mesh user ID: $fullId');
    }
    return fullId.substring(0, 16).toLowerCase();
  }

  /// Disconnect from the ESP32 and remove this phone's gateway advertisement.

  Future<void> disconnectEsp32() async {
    await _esp32Ble.disconnect();
    setEsp32Connected(false);
  }

  /// Send packet to ESP32 via BLE (as binary)
  /// This encodes the packet to binary format at the gateway

  Future<bool> sendToEsp32LoraGateway(Map<String, dynamic> packet) async {
    if (!isEsp32Connected.value) {
      _log("[LORA TX] ESP32 not connected");
      return false;
    }

    try {
      // Encode packet to binary using LoRaCodec
      final Uint8List loraBytes = LoRaCodec.encode(packet);
      _log("[LORA TX] Sending ${loraBytes.length} bytes to ESP32");

      return await _esp32Ble.sendData(loraBytes);
    } catch (e) {
      _log("[LORA TX] Encode error: $e");
      return false;
    }
  }

  /// Handle binary LoRa data received from ESP32 via BLE

  void handleLoraBytes(Uint8List bytes) {
    if (!isEsp32Connected.value) return;

    _log("[LORA RX] Received ${bytes.length} bytes from ESP32");

    // Decode binary packet
    final LoRaPacket? loraPacket = LoRaCodec.decode(bytes);
    if (loraPacket == null) {
      _log("[LORA RX] Failed to decode packet");
      return;
    }

    // Expand IDs from prefixes
    final String? fullTargetId = _expandTargetId(loraPacket.targetIdPrefix);
    if (fullTargetId == null) {
      _log("[LORA RX] Unknown target prefix: ${loraPacket.targetIdPrefix}");
      return;
    }

    final String? fullSenderId = _expandSenderId(loraPacket.senderIdPrefix);
    if (fullSenderId == null) {
      _log(
        "[LORA RX] Unknown sender prefix: ${loraPacket.senderIdPrefix}, dropped",
      );
      return;
    }

    // Check for duplicates
    if (!_rememberMessageId('lora_${loraPacket.messageId}')) {
      _log("[LORA RX] Duplicate ignored");
      return;
    }

    if (_isBlockedUser(fullSenderId)) return;

    _log(
      "[LORA RX] Message for ${_shortId(fullTargetId)} from ${_shortId(fullSenderId)}",
    );

    // Convert back to base64 for _deliverToMe
    final String bodyBase64 = base64Encode(loraPacket.encryptedBody);

    final bool isSeenReceipt = loraPacket.packetType == LoRaPacket.typeSeen;

    // Create packet map
    final Map<String, dynamic> packet = {
      'type': isSeenReceipt ? 'SEEN' : 'MSG',
      'messageId': loraPacket.messageId,
      'senderId': fullSenderId,
      'targetId': fullTargetId,
      'body': bodyBase64,
      'isLora': false,
      'ttl': _defaultTtl,
      'hopCount': 0,
      'viaLora': true,
    };

    if (fullTargetId == _currentUserId) {
      final Future<void> task = isSeenReceipt
          ? _deliverSeen(packet)
          : _deliverToMe(packet);
      task.catchError((Object e) {
        _log("LoRa delivery failed: $e");
      });
      return;
    }

    // Not for me - forward to mesh if target is in routing table
    if (!routingTable.containsKey(fullTargetId)) {
      _log("[LORA RX] Target ${_shortId(fullTargetId)} not in mesh, dropped");
      return;
    }

    _forwardPacket(packet);
  }

  /// Expand target ID from 8-byte prefix by matching routing table

  String? _expandTargetId(String prefix) {
    if (prefix.isEmpty) return null;

    // Check if it's me
    if (_currentUserId.startsWith(prefix)) {
      return _currentUserId;
    }

    // Search routing table
    for (final id in routingTable.keys) {
      if (id.startsWith(prefix)) {
        return id;
      }
    }

    return null; // Not found - packet will be dropped
  }

  /// Expand sender ID from 8-byte prefix by matching known profiles

  String? _expandSenderId(String prefix) {
    if (prefix.isEmpty) return null;

    // Check if it's me
    if (_currentUserId.startsWith(prefix)) {
      return _currentUserId;
    }

    // Search known profiles
    for (final id in knownProfiles.keys) {
      if (id.startsWith(prefix)) {
        return id;
      }
    }

    return null; // Not found - message won't decrypt
  }

  void handleLoraReceived(Map<String, dynamic> packet) {
    if (!isEsp32Connected.value) return;

    final messageId = packet['messageId'];
    final targetId = packet['targetId'];
    final senderId = packet['senderId'];
    final body = packet['body'];

    if (messageId is! String ||
        targetId is! String ||
        senderId is! String ||
        body is! String) {
      return;
    }

    if (_isBlockedUser(senderId)) return;

    if (!_rememberMessageId('lora_$messageId')) {
      _log("[LORA RX] duplicate ignored");
      return;
    }

    _log(
      "[LORA RX] message for ${_shortId(targetId)} from ${_shortId(senderId)}",
    );

    final Map<String, dynamic> injected = Map<String, dynamic>.from(packet);
    injected['isLora'] = false;
    injected.remove('gw');
    injected['ttl'] = _defaultTtl;
    injected['viaLora'] = true;

    if (targetId == _currentUserId) {
      _deliverToMe(injected).catchError((Object e) {
        _log("LoRa delivery failed: $e");
      });
      return;
    }

    if (!routingTable.containsKey(targetId)) {
      _log(
        "[LORA RX] target ${_shortId(targetId)} is not in my mesh, message dropped",
      );
      return;
    }

    _forwardPacket(injected);
  }
}
