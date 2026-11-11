import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get/get.dart';
import 'package:hop_talk/features/chat/models/chat_message.dart';
import 'package:hop_talk/features/chat/service/chat_storage_service.dart';
import 'package:hop_talk/features/home/controller/home_controller.dart';
import 'package:hop_talk/features/mesh_network/service/crypto_service.dart';
import 'package:location/location.dart' as loc;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/route_entry.dart';
import '../models/qr_contact.dart';
import '../models/lora_packet.dart';
import '../service/lora_codec.dart';
import '../service/esp32_ble_service.dart';

part 'permissions_extension.dart';
part 'connections_extension.dart';
part 'messaging_extension.dart';
part 'routing_extension.dart';
part 'esp32_extension.dart';
part 'contacts_extension.dart';

class MeshNetworkController extends GetxController {
  HomeController get _homeController => Get.find<HomeController>();
  ChatStorageService get _chatStorage => Get.find<ChatStorageService>();

  final CryptoService _crypto = CryptoService();
  final Esp32BleService _esp32Ble = Esp32BleService();
  StreamSubscription<bool>? _esp32ConnectionSub;
  StreamSubscription<Uint8List>? _esp32DataSub;
  Future<void>? _esp32InitialUserIdSyncTask;
  Future<void>? _esp32UserIdDeltaTask;
  final List<(String, bool)> _pendingEsp32UserIdDeltas = [];
  bool _esp32InitialUserIdSyncComplete = false;
  final Map<String, List<Map<String, dynamic>>> _pendingIncoming = {};
  final int _maxPendingPerSender = 20;

  late final _currentUserId = _homeController.userProfileData.value!.userId;
  late final _userName = _homeController.userProfileData.value?.name ?? 'User';
  late final _avatar = _homeController.userProfileData.value?.avatar ?? '';
  late final _compressedProfile =
      _homeController.userProfileData.value?.compressedImage ?? '';

  String get currentUserId => _currentUserId;
  String get publicKeyBase64 => _crypto.publicKeyBase64;

  String get myFingerprint =>
      QrContactData.fingerprintOf(_crypto.publicKeyBase64);

  static const String keyChangedError = 'KEY_CHANGED';

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

  var isEsp32Connected = false.obs;
  var isEsp32Scanning = false.obs;
  String? get esp32BleError => _esp32Ble.lastError;
  String? esp32UserIdSyncError;

  var connectedEndpoints = <String, String>{}.obs; // endpointId -> user name
  var discoveredDevices = <String, String>{}.obs; // endpointId -> user name
  var blockedDevices = <String>[].obs; // blocked userIds
  var knownUsers = <String, String>{}.obs; // userId -> user name
  var knownProfiles = <String, Map<String, dynamic>>{}
      .obs; // userId -> name, avatar, image, publicKey, version

  final StreamController<ChatMessage> _messageStreamController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageStreamController.stream;

  final StreamController<SeenUpdate> _seenStreamController =
      StreamController<SeenUpdate>.broadcast();
  Stream<SeenUpdate> get seenStream => _seenStreamController.stream;

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
        hasEsp32: isEsp32Connected.value,
      );
      unawaited(_sendInitialEsp32UserIds());

      await startMeshNode(_userName);
      _startRouteRefresh();
    } else {
      Get.snackbar(
        "Permission Required",
        "Bluetooth, Location & Nearby permissions are required for offline mesh.",
      );
    }
  }

  @override
  void onInit() {
    _esp32ConnectionSub = _esp32Ble.connectionStream.listen(setEsp32Connected);
    _esp32DataSub = _esp32Ble.dataStream.listen(handleLoraBytes);
    _loadSavedContacts();
    checkPermissions();
    super.onInit();
  }

  @override
  void onClose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _resetState(notify: false);
    _messageStreamController.close();
    _seenStreamController.close();
    _esp32ConnectionSub?.cancel();
    _esp32DataSub?.cancel();
    _esp32Ble.dispose();
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
