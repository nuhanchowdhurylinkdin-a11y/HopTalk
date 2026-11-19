import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';

import '../../controller/scanner_controller.dart';
import '../widgets/radar_wave_painter.dart';

class NearbyDevicesScreen extends StatelessWidget {
  const NearbyDevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ScannerController());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Searching for Nearby Devices'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screen = ScreenUtils.fromConstraints(constraints);
            final availableWidth =
                constraints.maxWidth - screen.horizontalPadding * 2;
            final radarSize = math
                .min(availableWidth, constraints.maxHeight * 0.62)
                .clamp(180.0, 360.0)
                .toDouble();

            return Column(
              children: [
                SizedBox(height: screen.isSmallPhone ? 12 : 20),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screen.horizontalPadding,
                  ),
                  child: Text(
                    'Looking for HopTalk peers around you...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF767964),
                      fontSize: screen.isSmallPhone ? 13 : 14,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox.square(
                      dimension: radarSize,
                      child: _buildRadar(controller, radarSize),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    screen.horizontalPadding,
                    screen.isSmallPhone ? 12 : 20,
                    screen.horizontalPadding,
                    screen.isSmallPhone ? 16 : 24,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: controller.meshController.initMeshNetwork,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.neutral,
                        minimumSize: Size(0, screen.isSmallPhone ? 46 : 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        'Restart Scanning',
                        style: TextStyle(
                          fontSize: screen.isSmallPhone ? 15 : 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRadar(ScannerController controller, double size) {
    final center = size / 2;
    final centerAvatarSize = size * 0.225;
    final peerNodeSize = size * 0.15;
    final nodeColumnWidth = math.min(size * 0.32, 108.0);
    final distance = size * 0.31;

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: controller.animationController,
          builder: (context, child) {
            return CustomPaint(
              size: Size.square(size),
              painter: RadarWavePainter(
                animation: controller.animationController,
                waveColor: AppColors.primary,
              ),
            );
          },
        ),
        Container(
          width: centerAvatarSize,
          height: centerAvatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: BuildProfileImage(
            profile: controller.homeController.userProfileData.value,
          ),
        ),
        Obx(() {
          final devices = controller.meshController.discoveredDevices.entries
              .toList();

          return Stack(
            children: List.generate(devices.length, (index) {
              final device = devices[index];
              final endpointId = device.key;
              final userName = device.value;
              final isConnected = controller.meshController.connectedEndpoints
                  .containsKey(endpointId);
              final isBlocked = controller.meshController.blockedDevices
                  .contains(endpointId);
              final angle = (index * 2 * math.pi) / math.max(devices.length, 1);
              final left =
                  (center + distance * math.cos(angle) - nodeColumnWidth / 2)
                      .clamp(0.0, size - nodeColumnWidth)
                      .toDouble();
              final top =
                  (center + distance * math.sin(angle) - peerNodeSize / 2)
                      .clamp(0.0, size - peerNodeSize - 22)
                      .toDouble();
              final statusColor = isBlocked
                  ? const Color(0xFFB42318)
                  : isConnected
                  ? AppColors.secondary
                  : AppColors.tertiary;

              return Positioned(
                left: left,
                top: top,
                width: nodeColumnWidth,
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'block') {
                      controller.meshController.blockDevice(endpointId);
                    } else if (value == 'unblock') {
                      controller.meshController.unblockDevice(endpointId);
                    } else if (value == 'connect') {
                      controller.meshController.manualConnectToDevice(
                        endpointId,
                      );
                    }
                  },
                  color: AppColors.background,
                  itemBuilder: (context) => [
                    if (!isBlocked && !isConnected)
                      const PopupMenuItem(
                        value: 'connect',
                        child: Text('Connect'),
                      ),
                    if (!isBlocked)
                      const PopupMenuItem(value: 'block', child: Text('Block')),
                    if (isBlocked)
                      const PopupMenuItem(
                        value: 'unblock',
                        child: Text('Unblock'),
                      ),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: peerNodeSize,
                        height: peerNodeSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primarySurface,
                          border: Border.all(color: statusColor, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          isBlocked
                              ? Icons.block
                              : isConnected
                              ? Icons.check_circle
                              : Icons.phone_android,
                          color: statusColor,
                          size: peerNodeSize * 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        constraints: BoxConstraints(maxWidth: nodeColumnWidth),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isBlocked
                              ? const Color(0xFFB42318)
                              : AppColors.neutral,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isBlocked ? '$userName (Blocked)' : userName,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        }),
      ],
    );
  }
}
