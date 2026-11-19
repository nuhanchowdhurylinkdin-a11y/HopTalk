import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/home/views/widgets/mesh_status.dart';
import 'package:hop_talk/features/permission/controller/permission_controller.dart';
import 'package:hop_talk/routes/app_routes.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(PermissionController());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        actions: [
          const MeshStatus(
            text: 'Setup Mode',
            dotColor: Color(0xFF767964),
          ).paddingOnly(right: 10),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screen = ScreenUtils.fromConstraints(constraints);

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screen.horizontalPadding,
                    vertical: screen.isSmallPhone ? 16 : 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Let's get you connected",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screen.isSmallPhone
                              ? 25
                              : screen.isLargePhone
                              ? 32
                              : 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: screen.isSmallPhone ? 8 : 12),
                      Text(
                        'Offline Messenger requires device hardware access to route peer-to-peer packets without cellular data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screen.descriptionSize,
                          height: 1.4,
                          fontWeight: FontWeight.w300,
                          color: const Color(0xFF454836),
                        ),
                      ),
                      SizedBox(height: screen.sectionGap),
                      Obx(
                        () => _buildPermissionTile(
                          screen: screen,
                          icon: Icons.bluetooth_searching,
                          title: 'Nearby devices',
                          subtitle: 'To find phones around you',
                          isEnabled:
                              controller.bluetoothScanGranted.value &&
                              controller.bluetoothAdvertiseGranted.value &&
                              controller.bluetoothConnectGranted.value,
                          onTap: () async {
                            await controller.requestSinglePermission(
                              Permission.bluetoothScan,
                            );
                            await controller.requestSinglePermission(
                              Permission.bluetoothAdvertise,
                            );
                            await controller.requestSinglePermission(
                              Permission.bluetoothConnect,
                            );
                          },
                        ),
                      ),
                      SizedBox(height: screen.isSmallPhone ? 8 : 12),
                      Obx(
                        () => _buildPermissionTile(
                          screen: screen,
                          icon: Icons.navigation_rounded,
                          rotate: 0.7,
                          title: 'Location',
                          subtitle: 'Required by Android for offline',
                          isEnabled: controller.locationGranted.value,
                          onTap: () => controller.requestSinglePermission(
                            Permission.location,
                          ),
                        ),
                      ),
                      SizedBox(height: screen.isSmallPhone ? 8 : 12),
                      Obx(
                        () => _buildPermissionTile(
                          screen: screen,
                          icon: Icons.wifi,
                          rotate: 0.8,
                          title: 'Nearby WiFi Devices',
                          subtitle: 'Optional - Android 13+',
                          isEnabled: controller.nearbyWifiGranted.value,
                          onTap: () => controller.requestSinglePermission(
                            Permission.nearbyWifiDevices,
                          ),
                        ),
                      ),
                      SizedBox(height: screen.isSmallPhone ? 8 : 12),
                      Obx(
                        () => _buildPermissionTile(
                          screen: screen,
                          icon: Icons.battery_charging_full,
                          title: 'Battery',
                          subtitle: 'Keep running in background',
                          isEnabled:
                              controller.batteryOptimizationDisabled.value,
                          onTap: controller.requestIgnoreBatteryOptimization,
                        ),
                      ),
                      SizedBox(height: screen.isSmallPhone ? 8 : 12),
                      Obx(
                        () => controller.batteryOptimizationDisabled.value
                            ? const SizedBox.shrink()
                            : Text(
                                '⚠️ Battery optimization may limit background messaging',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: screen.isSmallPhone ? 11 : 12,
                                  height: 1.35,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                      SizedBox(height: screen.sectionGap),
                      Obx(() {
                        final allCriticalGranted =
                            controller.bluetoothScanGranted.value &&
                            controller.bluetoothAdvertiseGranted.value &&
                            controller.bluetoothConnectGranted.value &&
                            controller.locationGranted.value;

                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: allCriticalGranted
                                ? () => Get.offAllNamed(AppRoutes.homeScreen)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.secondary,
                              disabledBackgroundColor: Colors.grey[300],
                              padding: EdgeInsets.symmetric(
                                vertical: screen.isSmallPhone ? 14 : 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Continue',
                              style: TextStyle(
                                fontSize: screen.isSmallPhone ? 15 : 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }),
                      SizedBox(height: screen.isSmallPhone ? 12 : 16),
                      Text(
                        'Grant all required permissions to proceed',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screen.isSmallPhone ? 11 : 12,
                          color: const Color(0xFF767964),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionTile({
    required ScreenUtils screen,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required VoidCallback onTap,
    double rotate = 0,
  }) {
    final iconSize = screen.isSmallPhone ? 40.0 : 44.0;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: screen.isSmallPhone ? 4 : 8,
      leading: Container(
        height: iconSize,
        width: iconSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFF0EDEF),
        ),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: rotate,
          child: Icon(
            icon,
            size: screen.isSmallPhone ? 21 : 24,
            color: const Color(0xFF454836),
          ),
        ),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: screen.isSmallPhone ? 15 : 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: screen.isSmallPhone ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
      ),
      trailing: isEnabled
          ? Container(
              height: 32,
              width: 32,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check,
                size: 22,
                color: AppColors.secondary,
              ),
            )
          : ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF0EDEF),
                foregroundColor: AppColors.neutral,
                elevation: 0,
                shadowColor: Colors.transparent,
                minimumSize: Size(screen.isSmallPhone ? 64 : 72, 40),
                padding: EdgeInsets.symmetric(
                  horizontal: screen.isSmallPhone ? 8 : 12,
                ),
              ),
              child: Text(
                'Allow',
                style: TextStyle(
                  fontSize: screen.isSmallPhone ? 12 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}
