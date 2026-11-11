part of 'mesh_network_controller.dart';

extension MeshConnections on MeshNetworkController {
  Future<void> startMeshNode(String localUserName) async {
    await startAdvertising(localUserName);
    await startDiscovery(localUserName);
  }

  Future<void> startAdvertising(String userName) async {
    try {
      bool result = await Nearby().startAdvertising(
        _encodeEndpointName(userName),
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: (String endpointId, ConnectionInfo info) {
          _onConnectionInitiated(endpointId, info);
        },
        onConnectionResult: (String endpointId, Status status) {
          _onConnectionResult(endpointId, status);
        },
        onDisconnected: (String endpointId) {
          _onDisconnected(endpointId);
        },
      );
      isAdvertising.value = result;
    } catch (e) {
      _log("Error starting advertising: $e");
    }
  }

  Future<void> startDiscovery(String userName) async {
    try {
      bool result = await Nearby().startDiscovery(
        _encodeEndpointName(userName),
        strategy,
        serviceId: serviceId,
        onEndpointFound: (String endpointId, String name, String serviceId) {
          final parsed = _parseEndpointName(name);
          if (_isSelf(parsed[0])) return;
          if (parsed[0].isNotEmpty) _endpointUserIds[endpointId] = parsed[0];
          _endpointNames[endpointId] = parsed[1];
          discoveredDevices[endpointId] = parsed[1];

          _considerConnecting(endpointId, userName);
        },
        onEndpointLost: (String? endpointId) {
          if (endpointId != null) {
            discoveredDevices.remove(endpointId);
            _retryCounts.remove(endpointId);
            update();
          }
        },
      );
      isDiscovering.value = result;
    } catch (e) {
      _log("Error starting discovery: $e");
    }
  }

  void _considerConnecting(String endpointId, String localUserName) {
    if (!_canConnectTo(endpointId)) return;

    final String remoteUserId = _endpointUserIds[endpointId] ?? '';
    final bool isInitiator =
        remoteUserId.isEmpty ||
        _shortId(_currentUserId).compareTo(_shortId(remoteUserId)) < 0;

    if (isInitiator) {
      _requestConnection(localUserName, endpointId);
      return;
    }

    Future.delayed(Duration(seconds: _fallbackConnectDelaySeconds), () {
      if (_canConnectTo(endpointId)) {
        _requestConnection(localUserName, endpointId);
      }
    });
  }

  bool _canConnectTo(String endpointId) {
    if (isClosed) return false;
    if (!discoveredDevices.containsKey(endpointId)) return false;
    if (connectedEndpoints.containsKey(endpointId)) return false;
    if (_pendingEndpoints.contains(endpointId)) return false;
    if (_isBlockedUser(_endpointUserIds[endpointId] ?? '')) return false;
    return true;
  }

  Future<void> _requestConnection(
    String localUserName,
    String endpointId,
  ) async {
    if (connectedEndpoints.containsKey(endpointId) ||
        _pendingEndpoints.contains(endpointId)) {
      return;
    }

    _pendingEndpoints.add(endpointId);

    try {
      await Nearby().requestConnection(
        _encodeEndpointName(localUserName),
        endpointId,
        onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
        onConnectionResult: (id, status) {
          _onConnectionResult(id, status);
          if (status != Status.CONNECTED) {
            _scheduleRetry(localUserName, id);
          }
        },
        onDisconnected: (id) => _onDisconnected(id),
      );
    } catch (e) {
      _pendingEndpoints.remove(endpointId);
      _log("Error requesting connection: $e");
      _scheduleRetry(localUserName, endpointId);
    }
  }

  void _scheduleRetry(String localUserName, String endpointId) {
    final int attempts = _retryCounts[endpointId] ?? 0;
    if (attempts >= _maxConnectionRetries) return;
    _retryCounts[endpointId] = attempts + 1;

    Future.delayed(Duration(seconds: 3 * (attempts + 1)), () {
      if (_canConnectTo(endpointId)) {
        _requestConnection(localUserName, endpointId);
      }
    });
  }

  Future<void> _onConnectionInitiated(
    String endpointId,
    ConnectionInfo info,
  ) async {
    final parsed = _parseEndpointName(info.endpointName);
    final String remoteUserId = parsed[0];

    if (_isBlockedUser(remoteUserId)) {
      _pendingEndpoints.remove(endpointId);
      try {
        await Nearby().rejectConnection(endpointId);
      } catch (e) {
        _log("Error rejecting connection: $e");
      }
      return;
    }

    _pendingEndpoints.add(endpointId);
    if (remoteUserId.isNotEmpty) _endpointUserIds[endpointId] = remoteUserId;
    _endpointNames[endpointId] = parsed[1];

    try {
      await Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: (String endpointId, Payload payload) {
          if (payload.type == PayloadType.BYTES && payload.bytes != null) {
            _handleIncomingPayload(endpointId, payload.bytes!);
          }
        },
      );
    } catch (e) {
      _pendingEndpoints.remove(endpointId);
      _log("Error accepting connection: $e");
    }
  }

  void _onConnectionResult(String endpointId, Status status) {
    _pendingEndpoints.remove(endpointId);

    if (status == Status.CONNECTED) {
      _retryCounts.remove(endpointId);
      connectedEndpoints[endpointId] =
          _endpointNames[endpointId] ??
          discoveredDevices[endpointId] ??
          endpointId;
      _sendHandshake(endpointId);
      update();
    } else {
      connectedEndpoints.remove(endpointId);
      update();
    }
  }

  void _onDisconnected(String endpointId) {
    connectedEndpoints.remove(endpointId);
    _pendingEndpoints.remove(endpointId);

    final bool routesChanged = _removeRoutesVia(endpointId);
    update();

    if (routesChanged) {
      _broadcastRoutingTable();
    }
  }

  void _sendHandshake(String endpointId) {
    Map<String, dynamic> handshakePacket = {
      "type": "HANDSHAKE",
      "userId": _currentUserId,
      "userName": _limitRunes(_userName, _maxProfileNameLength),
    };

    Uint8List bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(handshakePacket)),
    );
    _sendBytes(endpointId, bytes);
  }

  String _encodeEndpointName(String name) {
    return "${_shortId(_currentUserId)}|${_truncateUtf8(name, _maxEndpointNameBytes)}";
  }

  List<String> _parseEndpointName(String raw) {
    final int separator = raw.indexOf('|');
    if (separator <= 0) return ['', raw];
    return [raw.substring(0, separator), raw.substring(separator + 1)];
  }

  String _shortId(String id) {
    return id.length > _shortIdLength ? id.substring(0, _shortIdLength) : id;
  }

  String _truncateUtf8(String value, int maxBytes) {
    final StringBuffer buffer = StringBuffer();
    int used = 0;
    for (final rune in value.runes) {
      final String character = String.fromCharCode(rune);
      final int size = utf8.encode(character).length;
      if (used + size > maxBytes) break;
      buffer.write(character);
      used += size;
    }
    return buffer.toString();
  }

  String _limitRunes(String value, int maxRunes) {
    final List<int> runes = value.runes.toList();
    if (runes.length <= maxRunes) return value;
    return String.fromCharCodes(runes.sublist(0, maxRunes));
  }

  bool _sameUser(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    return a.startsWith(b) || b.startsWith(a);
  }

  bool _isSelf(String userId) {
    return _sameUser(_currentUserId, userId);
  }

  void manualConnectToDevice(String endpointId) {
    if (_isBlockedUser(_endpointUserIds[endpointId] ?? '')) return;

    _retryCounts.remove(endpointId);
    _requestConnection(_userName, endpointId);
  }

  void blockDevice(String endpointId) {
    final String? userId = _endpointUserIds[endpointId];
    if (userId == null || userId.isEmpty) return;

    if (!_isBlockedUser(userId)) {
      blockedDevices.add(userId);
    }

    final List<String> endpointsOfUser = _endpointUserIds.entries
        .where(
          (e) =>
              _sameUser(e.value, userId) &&
              connectedEndpoints.containsKey(e.key),
        )
        .map((e) => e.key)
        .toList();

    for (final id in endpointsOfUser) {
      _disconnectEndpoint(id);
    }

    update();
  }

  void unblockDevice(String userIdOrEndpointId) {
    final String userId =
        _endpointUserIds[userIdOrEndpointId] ?? userIdOrEndpointId;

    blockedDevices.removeWhere((blocked) => _sameUser(blocked, userId));

    final List<String> endpointsOfUser = _endpointUserIds.entries
        .where((e) => _sameUser(e.value, userId))
        .map((e) => e.key)
        .toList();

    for (final endpointId in endpointsOfUser) {
      _considerConnecting(endpointId, _userName);
    }

    update();
  }

  Future<void> _disconnectEndpoint(String endpointId) async {
    try {
      await Nearby().disconnectFromEndpoint(endpointId);
    } catch (e) {
      _log("Error disconnecting $endpointId: $e");
    }
    _onDisconnected(endpointId);
  }

  bool _isBlockedUser(String userId) {
    if (userId.isEmpty) return false;
    return blockedDevices.any((blocked) => _sameUser(blocked, userId));
  }
}
