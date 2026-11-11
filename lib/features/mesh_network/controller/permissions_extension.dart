part of 'mesh_network_controller.dart';

extension MeshPermissions on MeshNetworkController {
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
}
