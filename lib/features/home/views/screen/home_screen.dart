import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/home/controller/home_controller.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/home/views/widgets/mesh_status.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/routes/app_routes.dart';

import '../widgets/conversation_tile.dart';

class HomeScreen extends GetView<HomeController> {
  HomeScreen({super.key});

  final MeshNetworkController _ = Get.put(
    MeshNetworkController(),
    permanent: true,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              "Chats",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            SizedBox(width: 12),

            Obx(() {
              final isActive =
                  controller.meshController!.isAdvertising.value ||
                  controller.meshController!.isDiscovering.value;
              final discovered = controller.getDiscoveredDevicesCount();
              final connected = controller.getConnectedDevicesCount();

              return GestureDetector(
                // onTap: () => Get.toNamed(AppRoutes.permissionScreen),
                onTap: () => Get.toNamed(AppRoutes.nearbyDevicesScreen),
                child: MeshStatus(
                  dotColor: isActive ? Color(0xFF0053DB) : Colors.red,
                  text: isActive
                      ? "Connected Devices: $connected"
                      : "Mesh Inactive",
                ),
              );
            }),
          ],
        ),

        actions: [
          Obx(() {
            return CircleAvatar(
              radius: 40,
              backgroundColor: Colors.transparent,
              child: ClipOval(
                child: BuildProfileImage(
                  profile: controller.userProfileData.value,
                ),
              ),
            );
          }),

          if (kDebugMode)
            Obx(() {
              final mesh = controller.meshController!;
              return Switch(
                value: mesh.isEsp32Connected.value,
                onChanged: mesh.setEsp32Connected,
              );
            }),
        ],
      ),
      body: GetBuilder<MeshNetworkController>(
        builder: (mesh) {
          return Obx(() {
            final conversations = controller.conversations;

            if (conversations.isEmpty) {
              return const Center(
                child: Text("No chats yet. Nearby people will appear here."),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(() {
                  final isActive =
                      controller.meshController!.isAdvertising.value ||
                      controller.meshController!.isDiscovering.value;
                  final discovered = controller.getDiscoveredDevicesCount();

                  return Container(

                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    width: double.maxFinite,
                    decoration: BoxDecoration(
                      color: Color(0xFFF6F3F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isActive
                          ? "Mesh. $discovered Nearby Gateway"
                          : "No Device Found",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ).paddingSymmetric(horizontal: 16);
                }),
                Expanded(
                  child: ListView.separated(
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => ConversationTile(
                      conversation: conversations[index],
                      mesh: mesh,
                    ),
                  ),
                ),
              ],
            );
          });
        },
      ),
    );
  }
}
