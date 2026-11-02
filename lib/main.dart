import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hop_talk/core/services/storage_service.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';
import 'package:hop_talk/routes/app_routes.dart';
import 'package:hop_talk/core/utils/bindings/controller_binder.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await StorageService.init();
  await Hive.initFlutter();
  Hive.registerAdapter(UserProfileAdapter());
  await Hive.openBox<UserProfile>('userProfileBox');
  FlutterCryptography.enable();
  final initialRoute = await _determineInitialRoute();

  runApp(MyApp(initialRoute: initialRoute));
}

Future<String> _determineInitialRoute() async {
  final isOnboardingComplete = StorageService.isOnboardingComplete;
  final isSetupComplete = StorageService.isSetupComplete;

  if (!isOnboardingComplete) {
    return AppRoutes.onboardingScreen;
  }

  if (!isSetupComplete) {
    return AppRoutes.setupScreen;
  }

  // Check permissions
  bool bluetoothScan = await Permission.bluetoothScan.isGranted;
  bool bluetoothAdvertise = await Permission.bluetoothAdvertise.isGranted;
  bool bluetoothConnect = await Permission.bluetoothConnect.isGranted;
  bool location = await Permission.location.isGranted;

  bool arePermissionsGranted = bluetoothScan &&
      bluetoothAdvertise &&
      bluetoothConnect &&
      location;

  if (!arePermissionsGranted) {
    return AppRoutes.permissionScreen;
  }

  return AppRoutes.homeScreen;
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'HopTalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        fontFamily: 'Inter',
      ),
      initialRoute: initialRoute,
      getPages: AppRoutes.routes,
      initialBinding: ControllerBinder(),
    );
  }
}