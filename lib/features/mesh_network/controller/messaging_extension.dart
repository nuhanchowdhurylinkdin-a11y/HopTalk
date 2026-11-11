part of 'mesh_network_controller.dart';

extension MeshMessaging on MeshNetworkController {
  Future<void> _handleIncomingPayload(
    String senderEndpointId,
    Uint8List rawBytes,
  ) async {
    try {
      final String? endpointUserId = _endpointUserIds[senderEndpointId];
      if (endpointUserId != null && _isBlockedUser(endpointUserId)) return;

      final String jsonString = utf8.decode(rawBytes);
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) return;

      final Map<String, dynamic> packet = decoded;
      final type = packet["type"];

      if (type == "HANDSHAKE") {
        _handleHandshake(senderEndpointId, packet);
        return;
      } else if (type == 'ROUTING_UPDATE') {
        _processRoutingUpdate(senderEndpointId, packet);
        return;
      } else if (type == 'PROFILE') {
        _handleProfile(senderEndpointId, packet);
        return;
      }

      final messageId = packet['messageId'];
      final targetUserId = packet['targetId'];
      final senderId = packet['senderId'];
      final body = packet['body'];

      if (messageId is! String ||
          targetUserId is! String ||
          senderId is! String ||
          body is! String) {
        return;
      }

      if (_isBlockedUser(senderId)) return;

      if (!_rememberMessageId(messageId)) {
        return;
      }

      final bool isForLoraModule = packet['isLora'] == true;

      if (targetUserId == _currentUserId) {
        if (type == 'SEEN') {
          await _deliverSeen(packet);
        } else {
          await _deliverToMe(packet);
        }
        return;
      }

      if (isForLoraModule && packet['gw'] == _currentUserId) {
        if (isEsp32Connected.value) {
          await sendToEsp32LoraGateway(packet);
        } else {
          _log(
            "LoRa message dropped: I am the chosen gateway but ESP32 is not connected",
          );
        }
        return;
      }

      relayMessageToMesh(senderEndpointId, packet);
    } catch (e) {
      _log("Dropped invalid payload from $senderEndpointId: $e");
    }
  }

  Future<void> _deliverToMe(Map<String, dynamic> packet) async {
    final String senderId = packet['senderId'] as String;
    final String body = packet['body'] as String;

    final String? senderKey = knownProfiles[senderId]?['publicKey'] as String?;
    if (senderKey == null || senderKey.isEmpty) {
      final list = _pendingIncoming.putIfAbsent(senderId, () => []);
      if (list.length < _maxPendingPerSender) list.add(packet);
      return;
    }

    final String? plainText = await _crypto.decrypt(body, senderKey);
    if (plainText == null) {
      _log("Could not decrypt message from $senderId");
      return;
    }

    await _storeIncomingMessage(packet, plainText);
  }

  Future<void> _deliverSeen(Map<String, dynamic> packet) async {
    final String senderId = packet['senderId'] as String;
    final String body = packet['body'] as String;

    final String? senderKey = knownProfiles[senderId]?['publicKey'] as String?;
    if (senderKey == null || senderKey.isEmpty) return;

    final String? plain = await _crypto.decrypt(body, senderKey);
    if (plain == null) return;

    List<String> ids;
    try {
      final decoded = jsonDecode(plain);
      if (decoded is! List) return;
      ids = decoded.whereType<String>().take(100).toList();
    } catch (e) {
      return;
    }
    if (ids.isEmpty) return;

    List<String> updated = [];
    try {
      updated = await _chatStorage.markOutgoingSeen(senderId, ids.toSet());
    } catch (e) {
      _log("Could not store seen state: $e");
    }

    if (updated.isNotEmpty && !_seenStreamController.isClosed) {
      _seenStreamController.add(
        SeenUpdate(peerId: senderId, messageIds: updated),
      );
    }
  }

  Future<bool> sendSeenReceipt(String peerId, List<String> messageIds) async {
    if (messageIds.isEmpty || connectedEndpoints.isEmpty) return false;

    final String? peerKey = knownProfiles[peerId]?['publicKey'] as String?;
    if (peerKey == null || peerKey.isEmpty) return false;

    String encrypted;
    try {
      encrypted = await _crypto.encrypt(
        jsonEncode(messageIds.take(100).toList()),
        peerKey,
      );
    } catch (e) {
      _log("Receipt encryption failed: $e");
      return false;
    }

    final String receiptId = _generateMessageId();
    _rememberMessageId(receiptId);

    final Map<String, dynamic> packet = {
      "type": "SEEN",
      "isLora": false,
      "messageId": receiptId,
      "senderId": _currentUserId,
      "targetId": peerId,
      "body": encrypted,
      "hopCount": 0,
      "ttl": _defaultTtl,
    };

    return _forwardPacket(packet) > 0;
  }

  Future<void> _flushPendingFor(String userId) async {
    final List<Map<String, dynamic>>? list = _pendingIncoming.remove(userId);
    if (list == null) return;
    for (final packet in list) {
      await _deliverToMe(packet);
    }
  }

  void _handleHandshake(String senderEndpointId, Map<String, dynamic> packet) {
    final remoteUserId = packet["userId"];
    final remoteUserName = packet["userName"];

    if (remoteUserId is! String ||
        remoteUserId.isEmpty ||
        remoteUserId == _currentUserId) {
      return;
    }

    if (_isBlockedUser(remoteUserId)) {
      _disconnectEndpoint(senderEndpointId);
      return;
    }

    final String name = remoteUserName is String
        ? _limitRunes(remoteUserName, _maxProfileNameLength)
        : _shortId(remoteUserId);

    _endpointUserIds[senderEndpointId] = remoteUserId;
    _endpointNames[senderEndpointId] = name;
    knownUsers[remoteUserId] = name;
    connectedEndpoints[senderEndpointId] = name;

    _addDirectNeighbor(senderEndpointId, remoteUserId);
    _sendRoutingTableTo(senderEndpointId);
    _broadcastRoutingTable(exceptEndpointId: senderEndpointId);
    _sendProfilesTo(senderEndpointId, remoteUserId);
    update();
  }

  Uint8List _profileBytes({
    required String userId,
    required String name,
    required String avatar,
    required String image,
    required String publicKey,
    required int version,
  }) {
    final Map<String, dynamic> packet = {
      "type": "PROFILE",
      "userId": userId,
      "userName": _limitRunes(name, _maxProfileNameLength),
      "avatar": avatar,
      "image": image,
      "publicKey": publicKey,
      "version": version,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(packet)));
  }

  void _sendProfilesTo(String endpointId, String remoteUserId) {
    _sendBytes(
      endpointId,
      _profileBytes(
        userId: _currentUserId,
        name: _userName,
        avatar: _sanitizeAvatar(_avatar),
        image: _ownImage,
        publicKey: _crypto.publicKeyBase64,
        version: _profileVersion,
      ),
    );

    knownProfiles.forEach((userId, profile) {
      if (_sameUser(userId, remoteUserId)) return;
      if (profile['local'] == true) return;
      _sendBytes(
        endpointId,
        _profileBytes(
          userId: userId,
          name: (profile['name'] as String?) ?? '',
          avatar: (profile['avatar'] as String?) ?? '',
          image: (profile['image'] as String?) ?? '',
          publicKey: (profile['publicKey'] as String?) ?? '',
          version: (profile['version'] as int?) ?? 0,
        ),
      );
    });
  }

  void _handleProfile(String senderEndpointId, Map<String, dynamic> packet) {
    final userId = packet['userId'];
    final name = packet['userName'];
    final version = packet['version'];

    if (userId is! String || userId.isEmpty || _isSelf(userId)) return;
    if (name is! String || version is! int) return;
    if (_isBlockedUser(userId)) return;

    final String cleanPublicKey = _sanitizePublicKey(packet['publicKey']);
    if (cleanPublicKey.isEmpty) {
      _log("PROFILE dropped from $userId: missing or invalid publicKey");
      return;
    }

    final String cleanName = _limitRunes(name, _maxProfileNameLength);
    final String cleanAvatar = _sanitizeAvatar(packet['avatar']);
    final String cleanImage = _sanitizeImage(packet['image']);

    final Map<String, dynamic>? existing = knownProfiles[userId];
    bool shouldAccept;
    if (existing == null) {
      shouldAccept = true;
    } else {
      final String existingKey = (existing['publicKey'] as String?) ?? '';
      if (existingKey.isNotEmpty && existingKey != cleanPublicKey) return;

      final int existingVersion = (existing['version'] as int?) ?? 0;
      final String existingImage = (existing['image'] as String?) ?? '';
      if (version > existingVersion) {
        shouldAccept = true;
      } else if (version == existingVersion &&
          existingImage.isEmpty &&
          cleanImage.isNotEmpty) {
        shouldAccept = true;
      } else {
        shouldAccept = false;
      }
    }

    if (!shouldAccept) return;

    knownProfiles[userId] = {
      "name": cleanName,
      "avatar": cleanAvatar,
      "image": cleanImage,
      "publicKey": cleanPublicKey,
      "version": version,
    };
    knownUsers[userId] = cleanName;
    _log("PROFILE accepted for $userId");
    _applyProfileToRoutes(userId);

    _chatStorage
        .saveContact(
          peerId: userId,
          name: cleanName,
          avatar: cleanAvatar,
          image: cleanImage,
        )
        .catchError((Object e) {
          _log("Could not save contact: $e");
        });

    final Uint8List bytes = _profileBytes(
      userId: userId,
      name: cleanName,
      avatar: cleanAvatar,
      image: cleanImage,
      publicKey: cleanPublicKey,
      version: version,
    );

    for (final endpointId in connectedEndpoints.keys.toList()) {
      if (endpointId != senderEndpointId) {
        _sendBytes(endpointId, bytes);
      }
    }

    update();
    _flushPendingFor(userId);
  }

  String _sanitizeAvatar(dynamic value) {
    if (value is! String) return '';
    if (value.length > 64) return '';
    if (value.startsWith('assets/setup_avatars/') &&
        value.endsWith('.svg') &&
        !value.contains('..')) {
      return value;
    }
    return '';
  }

  String _sanitizePublicKey(dynamic value) {
    if (value is! String) return '';
    try {
      final Uint8List bytes = base64Decode(value);
      return bytes.length == 32 ? value : '';
    } catch (e) {
      return '';
    }
  }

  String _sanitizeImage(dynamic value) {
    if (value is! String || value.isEmpty) return '';
    if (value.length > _maxProfileImageChars) return '';
    try {
      final Uint8List bytes = base64Decode(value);
      if (bytes.length < 4) return '';
      final bool isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
      if (!isJpeg) return '';
      return value;
    } catch (e) {
      return '';
    }
  }

  Future<void> _storeIncomingMessage(
    Map<String, dynamic> packet,
    String plainText,
  ) async {
    final ChatMessage message = ChatMessage(
      messageId: packet['messageId'] as String,
      senderId: packet['senderId'] as String,
      targetId: packet['targetId'] as String,
      body: plainText,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      hopCount: packet['hopCount'] is int ? packet['hopCount'] as int : 0,
    );
    await _saveAndEmit(message.senderId, message, isIncoming: true);
  }

  Future<void> _saveAndEmit(
    String peerId,
    ChatMessage message, {
    required bool isIncoming,
  }) async {
    try {
      await _chatStorage.saveMessage(
        peerId: peerId,
        peerName: displayNameOf(peerId),
        message: message,
        isIncoming: isIncoming,
      );
    } catch (e) {
      _log("Could not save message: $e");
    }
    if (!_messageStreamController.isClosed) {
      _messageStreamController.add(message);
    }
  }

  void relayMessageToMesh(
    String originEndpointId,
    Map<String, dynamic> packet,
  ) {
    final int ttl = packet['ttl'] is int ? packet['ttl'] as int : 0;
    if (ttl <= 1) return;

    final int hopCount = packet['hopCount'] is int
        ? packet['hopCount'] as int
        : 0;

    final Map<String, dynamic> relayed = Map<String, dynamic>.from(packet);
    relayed['ttl'] = ttl - 1;
    relayed['hopCount'] = hopCount + 1;

    _forwardPacket(relayed, originEndpointId: originEndpointId);
  }

  int _forwardPacket(Map<String, dynamic> packet, {String? originEndpointId}) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(packet)));
    if (bytes.length > _maxPayloadBytes) return 0;

    final dynamic gateway = packet['gw'];
    final String routeKey = (packet['isLora'] == true && gateway is String)
        ? gateway
        : packet['targetId'] as String;

    final RouteEntry? route = routingTable[routeKey];
    if (route != null &&
        route.nextHopId != 'SELF' &&
        route.nextHopId != originEndpointId &&
        connectedEndpoints.containsKey(route.nextHopId)) {
      _sendBytes(route.nextHopId, bytes);
      return 1;
    }

    int sentCount = 0;
    for (final endpointId in connectedEndpoints.keys.toList()) {
      if (endpointId != originEndpointId) {
        _sendBytes(endpointId, bytes);
        sentCount++;
      }
    }
    return sentCount;
  }

  Future<void> _sendBytes(String endpointId, Uint8List bytes) async {
    if (bytes.length > _maxPayloadBytes) {
      _log("Payload too large (${bytes.length} bytes), not sent");
      return;
    }
    try {
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      _log("Error sending to $endpointId: $e");
    }
  }

  Future<bool> broadcastMessage(
    String targetUserId,
    String messageBody,
    bool isLora,
  ) async {
    final String? peerPublicKey =
        knownProfiles[targetUserId]?['publicKey'] as String?;
    if (peerPublicKey == null || peerPublicKey.isEmpty) {
      _log(
        "SEND FAIL: no public key for $targetUserId, known profiles: ${knownProfiles.keys.toList()}",
      );
      return false;
    }

    final RouteEntry? gateway = bestGateway();
    final bool hasRoute = routingTable.containsKey(targetUserId);
    final bool useLora = isLora || (!hasRoute && gateway != null);

    if (useLora && gateway == null) {
      _log("SEND FAIL: no LoRa gateway reachable");
      return false;
    }
    if (!useLora && !hasRoute && connectedEndpoints.isEmpty) {
      _log("SEND FAIL: no route and no connected endpoints");
      return false;
    }

    String encryptedBody;
    try {
      encryptedBody = await _crypto.encrypt(messageBody, peerPublicKey);
    } catch (e) {
      _log("SEND FAIL: encryption error $e");
      return false;
    }

    final String messageId = _generateMessageId();

    Map<String, dynamic> packet = {
      "isLora": useLora,
      "messageId": messageId,
      "senderId": _currentUserId,
      "targetId": targetUserId,
      "body": encryptedBody,
      "hopCount": 0,
      "ttl": _defaultTtl,
    };

    if (useLora) {
      packet["gw"] = gateway!.destinationId;
    }

    _rememberMessageId(messageId);

    int sentCount;
    if (useLora && gateway!.nextHopId == 'SELF') {
      // I am the gateway - encode and send via LoRa
      final bool sent = await sendToEsp32LoraGateway(packet);
      sentCount = sent ? 1 : 0;
    } else {
      // Send via mesh
      sentCount = _forwardPacket(packet);
    }

    if (sentCount == 0) {
      _log("SEND FAIL: nothing was sent");
      return false;
    }

    if (useLora) {
      _log(
        "Message queued for LoRa via gateway ${_shortId(gateway!.destinationId)}",
      );
    }

    await _saveAndEmit(
      targetUserId,
      ChatMessage(
        messageId: messageId,
        senderId: _currentUserId,
        targetId: targetUserId,
        body: messageBody,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
      isIncoming: false,
    );
    return true;
  }

  String _generateMessageId() {
    // Use LoRa codec's random 8-byte generator for all messages
    return LoRaCodec.generateMessageId();
  }

  bool _rememberMessageId(String messageId) {
    if (_processedMessageIds.contains(messageId)) return false;

    _processedMessageIds.add(messageId);
    if (_processedMessageIds.length > _maxCacheSize) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }
    return true;
  }
}
