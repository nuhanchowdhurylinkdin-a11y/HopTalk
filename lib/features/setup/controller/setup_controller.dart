import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:hop_talk/core/services/storage_service.dart';
import 'package:hop_talk/core/utils/helpers/app_helpers.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';
import 'package:hop_talk/routes/app_routes.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SetupController extends GetxController {
  final PageController avatarPageController = PageController();

  final List<String> avatars = [
    'assets/setup_avatars/avatar1.svg',
    'assets/setup_avatars/avatar2.svg',
    'assets/setup_avatars/avatar3.svg',
    'assets/setup_avatars/avatar4.svg',
    'assets/setup_avatars/avatar5.svg',
    'assets/setup_avatars/avatar6.svg',
    'assets/setup_avatars/avatar7.svg',
    'assets/setup_avatars/avatar8.svg',
    'assets/setup_avatars/avatar9.svg',
    'assets/setup_avatars/avatar10.svg',
    'assets/setup_avatars/avatar11.svg',
    'assets/setup_avatars/avatar12.svg',
    'assets/setup_avatars/avatar13.svg',
    'assets/setup_avatars/avatar14.svg',
    'assets/setup_avatars/avatar15.svg',
  ];

  final Box<UserProfile> _userProfileBox = Hive.box<UserProfile>(
    'userProfileBox',
  );
  final ImagePicker _picker = ImagePicker();

  final nameController = TextEditingController();

  final RxString name = ''.obs;
  final RxString selectedAvatar = ''.obs;
  final RxString profileImagePath = ''.obs;
  final RxInt currentAvatarPage = 0.obs;
  final RxBool isSaving = false.obs;

  static const int avatarsPerPage = 8;
  static const int maxNameLength = 30;
  static const int maxMeshImageChars = 12000;

  int get avatarPageCount => (avatars.length / avatarsPerPage).ceil();

  List<String> avatarsForPage(int pageIndex) {
    final start = pageIndex * avatarsPerPage;
    final end = (start + avatarsPerPage).clamp(0, avatars.length);

    return avatars.sublist(start, end);
  }

  void selectAvatar(String assetPath) {
    final String previousImagePath = profileImagePath.value;

    selectedAvatar.value = assetPath;
    profileImagePath.value = '';

    _deleteFileQuietly(previousImagePath);
  }

  Future<void> pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );

      if (pickedFile == null) return;

      final directory = await getApplicationDocumentsDirectory();

      final extension = p.extension(pickedFile.path).isEmpty
          ? '.jpg'
          : p.extension(pickedFile.path);

      final savedPath = p.join(
        directory.path,
        'profile_${DateTime.now().millisecondsSinceEpoch}$extension',
      );

      final savedFile = await File(pickedFile.path).copy(savedPath);

      final String previousImagePath = profileImagePath.value;

      profileImagePath.value = savedFile.path;
      selectedAvatar.value = '';

      if (previousImagePath != savedFile.path) {
        _deleteFileQuietly(previousImagePath);
      }
    } catch (e) {
      AppHelpers.showErrorSnackbar(
        title: 'Error!',
        message: 'Could not select profile image.',
      );
    }
  }

  Future<void> _deleteFileQuietly(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Could not delete old profile image: $e');
    }
  }

  Future<String?> _compressAndConvertToBase64(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final List<List<int>> attempts = [
        [128, 45],
        [96, 35],
        [64, 30],
      ];

      for (final attempt in attempts) {
        final Uint8List? compressedBytes =
        await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: attempt[0],
          minHeight: attempt[0],
          quality: attempt[1],
          format: CompressFormat.jpeg,
        );

        if (compressedBytes == null) return null;

        final String encoded = base64Encode(compressedBytes);
        if (encoded.length <= maxMeshImageChars) {
          return encoded;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Image compress error: $e');
      return null;
    }
  }

  Future<void> saveProfile() async {
    if (isSaving.value) return;

    final enteredName = nameController.text.trim();

    if (enteredName.isEmpty) {
      AppHelpers.showErrorSnackbar(
        title: 'Required',
        message: 'Please enter your name.',
      );
      return;
    }

    if (enteredName.runes.length > maxNameLength) {
      AppHelpers.showErrorSnackbar(
        title: 'Too long',
        message: 'Name can be at most $maxNameLength characters.',
      );
      return;
    }

    if (selectedAvatar.value.isEmpty && profileImagePath.value.isEmpty) {
      AppHelpers.showErrorSnackbar(
        title: 'Required',
        message: 'Please select a profile picture.',
      );
      return;
    }

    isSaving.value = true;

    try {
      final String salt = generateSecureSalt();

      final String userId = await generateCustomUserId(
        userName: enteredName,
        customSalt: salt,
      );

      String? imageBase64;
      if (profileImagePath.value.isNotEmpty) {
        imageBase64 = await _compressAndConvertToBase64(profileImagePath.value);
      }

      final profile = UserProfile(
        userId: userId,
        name: enteredName,
        avatar: selectedAvatar.value,
        imagePath: profileImagePath.value,
        compressedImage: imageBase64 ?? '',
      );

      await _userProfileBox.put('current', profile);
      name.value = enteredName;

      await StorageService.setSetupComplete(true);
      Get.offAllNamed(AppRoutes.permissionScreen);

      AppHelpers.showSuccessSnackbar(
        title: 'Success',
        message: 'Profile saved successfully.',
      );
    } catch (e) {
      AppHelpers.showErrorSnackbar(
        title: 'Error!',
        message: 'Could not save your profile.',
      );
    } finally {
      isSaving.value = false;
    }
  }

  String generateSecureSalt() {
    final random = math.Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> generateCustomUserId({
    required String userName,
    required String customSalt,
  }) async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String hardwareIdentifier = '';

      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        hardwareIdentifier = androidInfo.id;
      }

      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      String rawString =
          '${userName.trim()}_${hardwareIdentifier}_${timestamp}_$customSalt';

      var bytes = utf8.encode(rawString);
      var digest = sha256.convert(bytes);

      String uniqueId = digest.toString();
      return uniqueId;
    } catch (e) {
      return 'user_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  @override
  void onInit() {
    selectAvatar("assets/setup_avatars/avatar1.svg");
    super.onInit();
  }

  @override
  void onClose() {
    nameController.dispose();
    avatarPageController.dispose();
    super.onClose();
  }
}