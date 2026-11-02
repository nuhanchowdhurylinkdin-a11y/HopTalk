import 'dart:async';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get/get.dart';
import 'package:hop_talk/features/home/controller/home_controller.dart';
import 'package:hop_talk/features/mesh_network/service/crypto_service.dart';
import 'package:location/location.dart' as loc;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/route_entry.dart';

class MeshNetworkController extends GetxController {
  HomeController get _homeController => Get.find<HomeController>();

  final CryptoService _crypto = CryptoService();
  final Map<String, List<Map<String, dynamic>>> _pendingIncoming = {};
  final int _maxPendingPerSender = 20;

  late final _currentUserId = _homeController.userProfileData.value!.userId;
  late final _userName = _homeController.userProfileData.value?.name ?? 'User';
  late final _avatar = _homeController.userProfileData.value?.avatar ?? '';
  late final _compressedProfile =
      _homeController.userProfileData.value?.compressedImage ?? '';

  final String serviceId = "com.hoptalk.mesh";
  final Strategy strategy = Strategy.P2P_CLUSTER;

  var isPermissionsGranted = false.obs;
  var isAdvertising = false.obs;
  var isDiscovering = false.obs;

  var bluetoothScanGranted = false.obs;
  var bluetoothAdvertiseGranted = false.obs;
  var bluetoothConnectGranted = false.obs;
  var locationGranted = false.obs;
  var nearbyWifiGranted = false.obs;
  var batteryOptimizationDisabled = false.obs;

  var connectedEndpoints = <String, String>{}.obs; // endpointId -> user name
  var discoveredDevices = <String, String>{}.obs; // endpointId -> user name
  var blockedDevices = <String>[].obs; // blocked userIds
  var knownUsers = <String, String>{}.obs; // userId -> user name
  var knownProfiles =
      <String, Map<String, dynamic>>{}.obs; // userId -> name, avatar, image, publicKey, version
  var chatMessages = <Map<String, dynamic>>[].obs;

  void Function(Map<String, dynamic> message)? onMessageReceived;

  final Set<String> _processedMessageIds = {};
  final int _maxCacheSize = 200;

  final Map<String, RouteEntry> routingTable = {};

  final Set<String> _pendingEndpoints = {};
  final Map<String, int> _retryCounts = {};
  final Map<String, String> _endpointUserIds = {};
  final Map<String, String> _endpointNames = {};

  final int _defaultTtl = 16;
  final int _maxHops = 16;
  final int _maxPayloadBytes = 32 * 1024;
  final int _maxConnectionRetries = 3;
  final int _fallbackConnectDelaySeconds = 6;
  final int _routeRefreshSeconds = 30;
  final int _maxEndpointNameBytes = 40;
  final int _shortIdLength = 16;
  final int _maxProfileNameLength = 30;
  final int _maxProfileImageChars = 12000;

  int _messageCounter = 0;
  int? _sdkInt;
  Timer? _routeRefreshTimer;

  String _ownImage = '';
  int _profileVersion = 0;

  Future<void> initMeshNetwork() async {
    bool hasPermission = await checkAndRequestPermissions();
    if (hasPermission) {
      await _crypto.init();
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();

      _resetState();

      _profileVersion = DateTime.now().millisecondsSinceEpoch;
      _ownImage = await _buildMeshThumbnail(_compressedProfile);

      await Future.delayed(Duration(milliseconds: 500));

      routingTable[_currentUserId] = RouteEntry(
        destinationId: _currentUserId,
        nextHopId: 'SELF',
        hopCount: 0,
        avatar: _sanitizeAvatar(_avatar),
        imageByte: _ownImage,
      );

      await startMeshNode(_userName);
      _startRouteRefresh();
    } else {
      Get.snackbar(
        "Permission Required",
        "Bluetooth, Location & Nearby permissions are required for offline mesh.",
      );
    }
  }

  Future<String> _buildMeshThumbnail(String sourceBase64) async {
    if (sourceBase64.isEmpty) return '';
    if (sourceBase64.length <= _maxProfileImageChars) return sourceBase64;

    try {
      final Uint8List sourceBytes = base64Decode(sourceBase64);
      final List<List<int>> attempts = [
        [128, 45],
        [96, 35],
        [64, 30],
      ];

      for (final attempt in attempts) {
        final Uint8List result = await FlutterImageCompress.compressWithList(
          sourceBytes,
          minWidth: attempt[0],
          minHeight: attempt[0],
          quality: attempt[1],
          format: CompressFormat.jpeg,
        );
        final String encoded = base64Encode(result);
        if (encoded.length <= _maxProfileImageChars) return encoded;
      }
    } catch (e) {
      _log("Could not shrink profile image: $e");
    }
    return '';
  }

  Future<bool> checkAndRequestPermissions() async {
    await _refreshPermissionStates();

    final int sdk = await _getSdkInt();
    final List<Permission> missing = [];
    if (!bluetoothScanGranted.value) missing.add(Permission.bluetoothScan);
    if (!bluetoothAdvertiseGranted.value) {
      missing.add(Permission.bluetoothAdvertise);
    }
    if (!bluetoothConnectGranted.value) {
      missing.add(Permission.bluetoothConnect);
    }
    if (!locationGranted.value) missing.add(Permission.location);
    if (sdk >= 33 && !nearbyWifiGranted.value) {
      missing.add(Permission.nearbyWifiDevices);
    }

    if (missing.isNotEmpty) {
      await missing.request();
    }

    bool allGranted = await _refreshPermissionStates();
    if (!allGranted) {
      isPermissionsGranted.value = false;
      return false;
    }

    loc.Location locationService = loc.Location();

    bool isGpsEnabled = await locationService.serviceEnabled();
    if (!isGpsEnabled) {
      isGpsEnabled = await locationService.requestService();
      if (!isGpsEnabled) {
        isPermissionsGranted.value = false;
        return false;
      }
    }

    isPermissionsGranted.value = true;
    return true;
  }

  Future<bool> checkPermissions() async {
    bool allGranted = await _refreshPermissionStates();
    bool isGpsEnabled = await loc.Location().serviceEnabled();
    isPermissionsGranted.value = allGranted && isGpsEnabled;
    return isPermissionsGranted.value;
  }

  Future<bool> _refreshPermissionStates() async {
    final int sdk = await _getSdkInt();
    final bool needsNewBluetooth = sdk >= 31;
    final bool needsNearbyWifi = sdk >= 33;

    bluetoothScanGranted.value =
        !needsNewBluetooth || await Permission.bluetoothScan.isGranted;
    bluetoothAdvertiseGranted.value =
        !needsNewBluetooth || await Permission.bluetoothAdvertise.isGranted;
    bluetoothConnectGranted.value =
        !needsNewBluetooth || await Permission.bluetoothConnect.isGranted;
    locationGranted.value = await Permission.location.isGranted;
    nearbyWifiGranted.value =
        !needsNearbyWifi || await Permission.nearbyWifiDevices.isGranted;

    batteryOptimizationDisabled.value =
    await Permission.ignoreBatteryOptimizations.isGranted;

    return bluetoothScanGranted.value &&
        bluetoothAdvertiseGranted.value &&
        bluetoothConnectGranted.value &&
        locationGranted.value &&
        nearbyWifiGranted.value;
  }

  Future<int> _getSdkInt() async {
    if (_sdkInt != null) return _sdkInt!;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _sdkInt = info.version.sdkInt;
    } catch (e) {
      _sdkInt = 33;
    }
    return _sdkInt!;
  }

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
      final String currentUserId = _currentUserId;

      if (targetUserId == currentUserId) {
        await _deliverToMe(packet);
        return;
      }

      bool isConnectedToESP32 = false;
      if (isConnectedToESP32 && isForLoraModule) {
        // if ESP32 is connected and if the message is for LORA Gateway
        sendToEsp32LoraGateway(jsonString);
      } else {
        // if the message is for another just hop and push forword
        relayMessageToMesh(senderEndpointId, packet);
      }
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

    _storeIncomingMessage(packet, plainText);
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

  void _addDirectNeighbor(String endpointId, String userId) {
    routingTable[userId] = _newRoute(userId, endpointId, 1);
  }

  RouteEntry _newRoute(String destId, String nextHopId, int hopCount) {
    final Map<String, dynamic>? profile = knownProfiles[destId];
    return RouteEntry(
      destinationId: destId,
      nextHopId: nextHopId,
      hopCount: hopCount,
      avatar: (profile?['avatar'] as String?) ?? '',
      imageByte: (profile?['image'] as String?) ?? '',
    );
  }

  void _applyProfileToRoutes(String userId) {
    final RouteEntry? entry = routingTable[userId];
    if (entry == null) return;
    routingTable[userId] = _newRoute(userId, entry.nextHopId, entry.hopCount);
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
    _log("PROFILE accepted for $userId");
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
    _applyProfileToRoutes(userId);

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

  void _sendRoutingTableTo(String endpointId) {
    final List<Map<String, dynamic>> routesList = [];

    routingTable.forEach((desId, entry) {
      if (entry.nextHopId == endpointId) return;
      routesList.add({
        "destinationId": entry.destinationId,
        "hopCount": entry.hopCount,
      });
    });

    Map<String, dynamic> routingPacket = {
      "type": "ROUTING_UPDATE",
      "senderUserId": _currentUserId,
      "routes": routesList,
    };

    Uint8List bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(routingPacket)),
    );

    _sendBytes(endpointId, bytes);
  }

  void _broadcastRoutingTable({String? exceptEndpointId}) {
    for (final endpointId in connectedEndpoints.keys.toList()) {
      if (endpointId != exceptEndpointId) {
        _sendRoutingTableTo(endpointId);
      }
    }
  }

  void _processRoutingUpdate(
      String senderEndpointId,
      Map<String, dynamic> packet,
      ) {
    final routes = packet['routes'];
    if (routes is! List) return;

    bool isTableChanged = false;
    final Set<String> advertisedDestinations = {};

    for (final route in routes) {
      if (route is! Map) continue;

      final destId = route['destinationId'];
      final incomingHops = route['hopCount'];
      if (destId is! String || incomingHops is! int) continue;
      if (destId == _currentUserId) continue;

      final int calculatedHops = incomingHops + 1;
      if (calculatedHops > _maxHops) continue;

      advertisedDestinations.add(destId);

      final RouteEntry? existing = routingTable[destId];
      bool shouldReplace;
      if (existing == null) {
        shouldReplace = true;
      } else if (existing.nextHopId == senderEndpointId) {
        shouldReplace = existing.hopCount != calculatedHops;
      } else {
        shouldReplace = existing.hopCount > calculatedHops;
      }

      if (shouldReplace) {
        routingTable[destId] = _newRoute(
          destId,
          senderEndpointId,
          calculatedHops,
        );
        isTableChanged = true;
      }
    }

    final List<String> staleDestinations = routingTable.entries
        .where(
          (e) =>
      e.value.nextHopId == senderEndpointId &&
          !advertisedDestinations.contains(e.key),
    )
        .map((e) => e.key)
        .toList();

    for (final destId in staleDestinations) {
      routingTable.remove(destId);
      isTableChanged = true;
    }

    if (isTableChanged) {
      _broadcastRoutingTable(exceptEndpointId: senderEndpointId);
      update();
    }
  }

  bool _removeRoutesVia(String endpointId) {
    final List<String> destinations = routingTable.entries
        .where((e) => e.value.nextHopId == endpointId)
        .map((e) => e.key)
        .toList();

    for (final destId in destinations) {
      routingTable.remove(destId);
    }
    return destinations.isNotEmpty;
  }

  void _startRouteRefresh() {
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer.periodic(
      Duration(seconds: _routeRefreshSeconds),
          (_) => _broadcastRoutingTable(),
    );
  }

  void _storeIncomingMessage(Map<String, dynamic> packet, String plainText) {
    final Map<String, dynamic> message = {
      "messageId": packet['messageId'],
      "senderId": packet['senderId'],
      "targetId": packet['targetId'],
      "body": plainText,
      "hopCount": packet['hopCount'] is int ? packet['hopCount'] : 0,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "isMine": false,
    };

    chatMessages.add(message);
    onMessageReceived?.call(message);
    update();
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

    final RouteEntry? route = routingTable[packet['targetId']];
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

  void sendToEsp32LoraGateway(String payloadString) {
    _log("Forwarded to LoRa via ESP32");
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
    if (connectedEndpoints.isEmpty) {
      _log("SEND FAIL: no connected endpoints");
      return false;
    }

    final String? peerPublicKey =
    knownProfiles[targetUserId]?['publicKey'] as String?;
    if (peerPublicKey == null || peerPublicKey.isEmpty) {
      _log(
        "SEND FAIL: no public key for $targetUserId, known profiles: ${knownProfiles.keys.toList()}",
      );
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
      "isLora": isLora,
      "messageId": messageId,
      "senderId": _currentUserId,
      "targetId": targetUserId,
      "body": encryptedBody,
      "hopCount": 0,
      "ttl": _defaultTtl,
    };

    _rememberMessageId(messageId);

    final int sentCount = _forwardPacket(packet);
    if (sentCount == 0) {
      _log("SEND FAIL: forwardPacket sent 0 (payload too large or no endpoint)");
      return false;
    }

    chatMessages.add({
      "messageId": messageId,
      "senderId": _currentUserId,
      "targetId": targetUserId,
      "body": messageBody,
      "hopCount": 0,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "isMine": true,
    });
    update();
    return true;
  }

  String _generateMessageId() {
    _messageCounter++;
    return "${_shortId(_currentUserId)}_${DateTime.now().microsecondsSinceEpoch}_$_messageCounter";
  }

  bool _rememberMessageId(String messageId) {
    if (_processedMessageIds.contains(messageId)) return false;

    _processedMessageIds.add(messageId);
    if (_processedMessageIds.length > _maxCacheSize) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }
    return true;
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

  Future<void> requestSinglePermission(Permission permission) async {
    final int sdk = await _getSdkInt();

    final bool isNewBluetooth =
        permission == Permission.bluetoothScan ||
            permission == Permission.bluetoothAdvertise ||
            permission == Permission.bluetoothConnect;
    final bool isNearbyWifi = permission == Permission.nearbyWifiDevices;

    if ((isNewBluetooth && sdk < 31) || (isNearbyWifi && sdk < 33)) {
      await checkPermissions();
      return;
    }

    PermissionStatus status = await permission.request();

    if (status.isPermanentlyDenied) {
      Get.dialog(
        AlertDialog(
          title: Text("Permission Required"),
          content: Text("Please enable this permission in app settings"),
          actions: [
            TextButton(onPressed: () => Get.back(), child: Text("Cancel")),
            TextButton(
              onPressed: () {
                openAppSettings();
                Get.back();
              },
              child: Text("Open Settings"),
            ),
          ],
        ),
      );
    }

    await checkPermissions();
  }

  Future<void> requestIgnoreBatteryOptimization() async {
    PermissionStatus status = await Permission.ignoreBatteryOptimizations
        .request();
    batteryOptimizationDisabled.value = status.isGranted;

    if (status.isDenied || status.isPermanentlyDenied) {
      Get.dialog(
        AlertDialog(
          title: Text("Battery Optimization"),
          content: Text(
            "For continuous mesh networking, please disable battery optimization. "
                "This keeps HopTalk running in the background to relay messages.",
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: Text("Cancel")),
            TextButton(
              onPressed: () {
                openAppSettings();
                Get.back();
              },
              child: Text("Open Settings"),
            ),
          ],
        ),
      );
    }
  }

  List<RouteEntry> get reachableRoutes {
    final List<RouteEntry> list = routingTable.values
        .where((e) => e.nextHopId != 'SELF')
        .toList();

    list.sort((a, b) {
      final int byHops = a.hopCount.compareTo(b.hopCount);
      if (byHops != 0) return byHops;
      return displayNameOf(a.destinationId).compareTo(
        displayNameOf(b.destinationId),
      );
    });

    return list;
  }

  String displayNameOf(String userId) {
    final String? name = knownUsers[userId];
    if (name != null && name.isNotEmpty) return name;
    return userId.length > 6 ? userId.substring(0, 6) : userId;
  }

  @override
  void onInit() {
    checkPermissions();
    super.onInit();
  }

  @override
  void onClose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _resetState(notify: false);
    super.onClose();
  }

  void _resetState({bool notify = true}) {
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = null;

    routingTable.clear();
    connectedEndpoints.clear();
    discoveredDevices.clear();
    _pendingEndpoints.clear();
    _retryCounts.clear();
    _endpointUserIds.clear();
    _endpointNames.clear();
    _pendingIncoming.clear();

    isAdvertising.value = false;
    isDiscovering.value = false;

    if (notify) update();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint("[Mesh] $message");
  }
}