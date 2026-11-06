import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/home/controller/home_controller.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/home/views/widgets/lora_tab.dart';
import 'package:hop_talk/features/home/views/widgets/mesh_status.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/features/qr/views/qr_screen.dart';
import 'package:hop_talk/routes/app_routes.dart';

import '../widgets/conversation_tile.dart';

class HomeScreen extends GetView<HomeController> {
  HomeScreen({super.key}) {
    Get.put(
      MeshNetworkController(),
      permanent: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Row(
            children: [
              const Text(
                "HopTalk",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Obx(() {
                final meshController = controller.meshController;
                if (meshController == null) {
                  return const SizedBox.shrink();
                }

                final isActive =
                    meshController.isAdvertising.value ||
                    meshController.isDiscovering.value;
                final connected = controller.getConnectedDevicesCount();

                return GestureDetector(
                  onTap: () => Get.toNamed(AppRoutes.nearbyDevicesScreen, arguments: isActive),
                  child: MeshStatus(
                    dotColor: isActive ? const Color(0xFF0053DB) : Colors.red,
                    text: isActive
                        ? "C: $connected"
                        : "Mesh Inactive",
                  ),
                );
              }),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => Get.to(() => const QrScreen()),
            ),
            Obx(() {
              return GestureDetector(
                onTap: () => Get.toNamed(AppRoutes.meScreen),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.transparent,
                  child: ClipOval(
                    child: BuildProfileImage(
                      profile: controller.userProfileData.value,
                    ),
                  ),
                ),
              );
            }),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Chats"),
              Tab(text: "LoRa"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ChatsTab(controller: controller),
            const LoraTab(),
          ],
        ),
      ),
    );
  }
}

class _ChatsTab extends StatelessWidget {
  const _ChatsTab({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MeshNetworkController>(
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
                final meshController = controller.meshController;
                if (meshController == null) {
                  return const SizedBox.shrink();
                }

                final isActive =
                    meshController.isAdvertising.value ||
                    meshController.isDiscovering.value;
                final discovered = controller.getDiscoveredDevicesCount();

                return Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  width: double.maxFinite,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F3F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isActive
                        ? "Mesh. $discovered Nearby Gateway"
                        : "No Device Found",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ).paddingSymmetric(horizontal: 16);
              }),
              Expanded(
                child: ListView.separated(
                  itemCount: conversations.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
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
    );
  }
}
