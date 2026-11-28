import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/helpers/app_helpers.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/chat/service/chat_storage_service.dart';
import 'package:hop_talk/features/chat/views/screens/chat_screen.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/routes/app_routes.dart';
import 'package:hop_talk/features/qr/views/qr_screen.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';

class LoraTab extends StatelessWidget {
  const LoraTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MeshNetworkController>(
      builder: (mesh) {
        return Obx(() {
          final ChatStorageService storage = Get.find<ChatStorageService>();
          final List<Map<String, dynamic>> qrContacts = storage.getQrContacts();
          final bool esp32Connected = mesh.isEsp32Connected.value;
          final bool hasGateway = mesh.bestGateway() != null;
          final screen = ScreenUtils.of(context);

          return ListView(
            padding: EdgeInsets.all(screen.horizontalPadding),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    children: [
                      _buildEsp32Card(mesh, esp32Connected, screen),
                      SizedBox(height: screen.sectionGap * 0.7),
                      _buildFirmwareCard(screen),
                      SizedBox(height: screen.sectionGap * 0.7),
                      _buildGatewaysSection(mesh, screen),
                      SizedBox(height: screen.sectionGap * 0.7),
                      _buildQrContactsSection(
                        mesh,
                        storage,
                        qrContacts,
                        hasGateway,
                        screen,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildFirmwareCard(ScreenUtils screen) {
    return Card(
      color: AppColors.primarySurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(screen.isSmallPhone ? 12 : 16),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt, color: AppColors.secondary),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ESP32 Firmware',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('Update firmware over USB OTG.'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => Get.toNamed(AppRoutes.flashFirmwareScreen),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF202124),
              ),
              child: const Text('Flash'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEsp32Card(
    MeshNetworkController mesh,
    bool connected,
    ScreenUtils screen,
  ) {
    return Card(
      color: AppColors.primarySurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(screen.isSmallPhone ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.check_circle : Icons.cancel,
                  color: connected
                      ? AppColors.secondary
                      : const Color(0xFF767964),
                ),
                const SizedBox(width: 8),
                Text(
                  connected ? "ESP32 Connected" : "ESP32 Not Connected",
                  style: TextStyle(
                    fontSize: screen.isSmallPhone ? 15 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (connected)
              OutlinedButton.icon(
                onPressed: mesh.disconnectEsp32,
                icon: const Icon(Icons.bluetooth_disabled),
                label: const Text('Disconnect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                ),
              )
            else
              Obx(
                () => ElevatedButton.icon(
                  onPressed: mesh.isEsp32Scanning.value
                      ? null
                      : () => _scanAndConnect(mesh),
                  icon: mesh.isEsp32Scanning.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(
                    mesh.isEsp32Scanning.value
                        ? 'Scanning…'
                        : 'Scan and connect',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.neutral,
                    disabledBackgroundColor: AppColors.background,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanAndConnect(MeshNetworkController mesh) async {
    final List<ScanResult> devices = await mesh.scanEsp32Devices();
    if (devices.isEmpty) {
      AppHelpers.showErrorSnackbar(
        title: 'ESP32 not found',
        message: 'Check that the board is powered on and advertising the configured service UUID.',
      );
      return;
    }

    final ScanResult? selected = await Get.dialog<ScanResult>(
      AlertDialog(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Choose ESP32'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: devices
                .map(
                  (result) => ListTile(
                    leading: const Icon(
                      Icons.developer_board,
                      color: AppColors.secondary,
                    ),
                    title: Text(
                      result.device.platformName.isEmpty
                          ? 'ESP32 (${result.device.remoteId.str})'
                          : result.device.platformName,
                    ),
                    subtitle: Text(result.device.remoteId.str),
                    onTap: () => Get.back(result: result),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;

    final connected = await mesh.connectEsp32(selected.device);
    if (!connected) {
      AppHelpers.showErrorSnackbar(
        title: 'Connection failed',
        message:
            mesh.esp32BleError ??
            'ESP32 BLE connection failed. Check device logs.',
      );
    } else if (mesh.esp32UserIdSyncError != null) {
      AppHelpers.showErrorSnackbar(
        title: 'ESP32 connected; ID sync failed',
        message: mesh.esp32UserIdSyncError!,
      );
    } else {
      AppHelpers.showSuccessSnackbar(
        title: 'ESP32 connected',
        message: 'Your LoRa gateway is ready to use.',
      );
    }
  }

  Widget _buildGatewaysSection(MeshNetworkController mesh, ScreenUtils screen) {
    final List<dynamic> gateways = mesh.gateways;
    final dynamic bestGw = mesh.bestGateway();

    return Card(
      color: AppColors.primarySurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(screen.isSmallPhone ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Gateways in mesh",
              style: TextStyle(
                fontSize: screen.isSmallPhone ? 15 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (gateways.isEmpty)
              const Text(
                "No LoRa gateways found in the mesh network",
                style: TextStyle(color: Colors.black54),
              )
            else
              for (final gw in gateways)
                Builder(
                  builder: (context) {
                    final bool isSelf = gw.nextHopId == 'SELF';
                    final bool isBest =
                        bestGw != null &&
                        gw.destinationId == bestGw.destinationId;
                    final String name = isSelf
                        ? "This phone"
                        : mesh.displayNameOf(gw.destinationId);
                    final String hopInfo = isSelf
                        ? ""
                        : " (${gw.hopCount} ${gw.hopCount == 1 ? 'hop' : 'hops'} away)";

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cell_tower,
                            size: 20,
                            color: isBest
                                ? AppColors.secondary
                                : const Color(0xFF767964),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text("$name$hopInfo")),
                          if (isBest)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "Best",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrContactsSection(
    MeshNetworkController mesh,
    ChatStorageService storage,
    List<Map<String, dynamic>> qrContacts,
    bool hasGateway,
    ScreenUtils screen,
  ) {
    return Card(
      color: AppColors.primarySurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(screen.isSmallPhone ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  'QR contacts',
                  style: TextStyle(
                    fontSize: screen.isSmallPhone ? 15 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                );
                final action = ElevatedButton.icon(
                  onPressed: () => Get.to(() => const QrScreen()),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Show / scan QR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.neutral,
                    padding: EdgeInsets.symmetric(
                      horizontal: screen.isSmallPhone ? 10 : 14,
                    ),
                  ),
                );

                if (constraints.maxWidth < 340) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), action],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [title, action],
                );
              },
            ),
            const SizedBox(height: 12),
            if (qrContacts.isEmpty)
              const Text(
                "No QR contacts yet. Add contacts to message them over LoRa when out of mesh range.",
                style: TextStyle(color: Colors.black54),
              )
            else
              for (final contact in qrContacts)
                Builder(
                  builder: (context) {
                    final String peerId = contact['peerId'] as String;
                    final String name = (contact['peerName'] as String?) ?? '';
                    final String avatar = (contact['avatar'] as String?) ?? '';
                    final String image = (contact['image'] as String?) ?? '';

                    final dynamic route = mesh.routingTable[peerId];
                    final bool isInMesh =
                        route != null && route.nextHopId != 'SELF';

                    String status;
                    if (isInMesh) {
                      status = "In mesh range";
                    } else if (hasGateway) {
                      status = "Reachable via LoRa";
                    } else {
                      status = "No path";
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.transparent,
                            child: ClipOval(
                              child: BuildProfileImage(
                                profile: UserProfile(
                                  userId: peerId,
                                  name: name,
                                  avatar: avatar,
                                  imagePath: '',
                                  compressedImage: image,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isInMesh
                                        ? AppColors.secondary
                                        : hasGateway
                                        ? AppColors.tertiary
                                        : const Color(0xFF767964),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.chat,
                              color: AppColors.secondary,
                            ),
                            onPressed: () => Get.to(
                              () => ChatScreen(
                                peerId: peerId,
                                peerName: name,
                                avatar: avatar,
                                imageByte: image,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Color(0xFFB42318),
                            ),
                            onPressed: () =>
                                _confirmDelete(storage, mesh, peerId, name),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    ChatStorageService storage,
    MeshNetworkController mesh,
    String peerId,
    String name,
  ) async {
    final bool? confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text("Delete Contact"),
        content: Text(
          "Are you sure you want to delete $name? The chat history will also be deleted.",
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await storage.deleteConversation(peerId);
      mesh.forgetContact(peerId);
      Get.snackbar(
        "Contact Deleted",
        "$name has been removed",
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
