import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/home/controller/home_controller.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/home/views/widgets/mesh_status.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';
import 'package:hop_talk/routes/app_routes.dart';

import '../../../chat/views/chat_screen.dart';

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
                      ? "D:$discovered C:$connected"
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
        ],
      ),
      body: GetBuilder<MeshNetworkController>(
        builder: (mesh) {
          final routes = mesh.reachableRoutes;

          if (routes.isEmpty) {
            return const Center(child: Text("No devices in the mesh yet"));
          }

          return ListView.separated(
            itemCount: routes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final route = routes[index];
              final name = mesh.displayNameOf(route.destinationId);

              return ListTile(
                onTap: () => Get.to(
                      () => ChatScreen(
                    peerId: route.destinationId,
                    peerName: name,
                    avatar: route.avatar,
                    imageByte: route.imageByte,
                  ),
                ),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.transparent,
                  child: ClipOval(
                    child: BuildProfileImage(
                      profile: UserProfile(
                        userId: route.destinationId,
                        name: name,
                        avatar: route.avatar,
                        imagePath: '',
                        compressedImage: route.imageByte,
                      ),
                    ),
                  ),
                ),
                title: Text(name),
                subtitle: Text(
                  route.hopCount == 1 ? "Direct" : "${route.hopCount} hops",
                ),
              );
            },
          );
        },
      ),
    );
  }
}
