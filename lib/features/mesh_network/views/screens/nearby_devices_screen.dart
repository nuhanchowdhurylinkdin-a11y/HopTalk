import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
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
        title: const Text("Searching for Nearby Devices"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              "Looking for HopTalk peers around you...",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            Expanded(
              child: Center(
                // Stack places the radar rings underneath and scattered device icons on top
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Radar Background Ripples
                      AnimatedBuilder(
                        animation: controller.animationController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(320, 320),
                            painter: RadarWavePainter(
                              animation: controller.animationController,
                              waveColor: AppColors.primary,
                            ),
                          );
                        },
                      ),

                      // 2. Center Node --> Avatar
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: BuildProfileImage(
                          profile: controller.homeController.userProfileData.value,
                        ),
                      ),

                      // 3. Discovered Peer Nodes Placed Dynamically with Full Logic
                      Obx(() {
                        final devices = controller
                            .meshController
                            .discoveredDevices
                            .entries
                            .toList();

                        return Stack(
                          children: List.generate(devices.length, (index) {
                            final device = devices[index];
                            final endpointId = device.key;
                            final userName = device.value;

                            // Check statuses using meshController
                            final isConnected = controller.meshController.connectedEndpoints.containsKey(endpointId);
                            final isBlocked = controller.meshController.blockedDevices.contains(endpointId);

                            // Scatter nodes dynamically based on index angles
                            final angle = (index * 2 * math.pi) / math.max(devices.length, 1);
                            const distance = 100.0;

                            final x = 160.0 + distance * math.cos(angle) - 24;
                            final y = 160.0 + distance * math.sin(angle) - 24;

                            return Positioned(
                              left: x,
                              top: y,
                              child: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'block') {
                                    controller.meshController.blockDevice(endpointId);
                                  } else if (value == 'unblock') {
                                    controller.meshController.unblockDevice(endpointId);
                                  } else if (value == 'connect') {
                                    controller.meshController.manualConnectToDevice(endpointId);
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (!isBlocked && !isConnected)
                                    const PopupMenuItem(value: 'connect', child: Text('Connect')),
                                  if (!isBlocked)
                                    const PopupMenuItem(value: 'block', child: Text('Block')),
                                  if (isBlocked)
                                    const PopupMenuItem(value: 'unblock', child: Text('Unblock')),
                                ],
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        border: Border.all(
                                          color: isBlocked
                                              ? Colors.red
                                              : isConnected
                                              ? Colors.green
                                              : const Color(0xFF0053DB),
                                          width: 2,
                                        ),
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
                                        color: isBlocked
                                            ? Colors.red
                                            : isConnected
                                            ? Colors.green
                                            : const Color(0xFF0053DB),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isBlocked ? Colors.red[700] : Colors.black87,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        isBlocked ? "$userName (Blocked)" : userName,
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
                  ),
                ),
              ),
            ),

            // Bottom Action
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  // restart scanning
                  controller.meshController.initMeshNetwork();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(Icons.refresh, color: AppColors.neutral),
                label: Text(
                  "Restart Scanning",
                  style: TextStyle(color: AppColors.neutral, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
