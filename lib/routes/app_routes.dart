import 'package:get/route_manager.dart';
import 'package:hop_talk/features/home/views/screen/home_screen.dart';
import 'package:hop_talk/features/me/views/screens/me_screen.dart';
import 'package:hop_talk/features/mesh_network/views/screens/nearby_devices_screen.dart';
import 'package:hop_talk/features/permission/views/screens/permission_screen.dart';
import 'package:hop_talk/features/onboarding/views/screens/onboarding_screen.dart';
import 'package:hop_talk/features/setup/views/setup_screen.dart';

class AppRoutes {
  static String onboardingScreen = "/onboardingScreen";
  static String setupScreen = "/setupScreen";
  static String homeScreen = "/homeScreen";
  static String permissionScreen = "/permissionScreen";
  static String nearbyDevicesScreen = "/nearbyDevicesScreen";
  static String meScreen = "/meScreen";

  static List<GetPage> routes =[
    GetPage(name: onboardingScreen, page: () => const OnboardingScreen()),
    GetPage(name: setupScreen, page: () => const SetupScreen()),
    GetPage(name: homeScreen, page: () =>  HomeScreen()),
    GetPage(name: permissionScreen, page: () => const PermissionScreen()),
    GetPage(name: nearbyDevicesScreen, page: () => const NearbyDevicesScreen()),
    GetPage(name: meScreen, page: () {
      final bool isActive = Get.arguments ?? false;
      return MeScreen(isActive: isActive);
    }),
  ];
}