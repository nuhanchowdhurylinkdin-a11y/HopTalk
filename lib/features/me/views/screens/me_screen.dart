import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/helpers/app_helpers.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/home/controller/home_controller.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/home/views/widgets/mesh_status.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key, required this.isActive});

  final bool isActive;

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  static const List<String> _avatars = [
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

  final ImagePicker _imagePicker = ImagePicker();
  final Set<String> _temporaryImagePaths = {};
  late final HomeController _homeController;
  late final TextEditingController _nameController;
  UserProfile? _originalProfile;
  String _avatar = '';
  String _imagePath = '';
  String _compressedImage = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _homeController = Get.find<HomeController>();
    _originalProfile = _homeController.userProfileData.value;
    _avatar = _originalProfile?.avatar ?? '';
    _imagePath = _originalProfile?.imagePath ?? '';
    _compressedImage = _originalProfile?.compressedImage ?? '';
    _nameController = TextEditingController(text: _originalProfile?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final path in _temporaryImagePaths) {
      unawaited(_deleteImage(path));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: MeshStatus(
                text: widget.isActive ? 'Mesh Active' : 'Mesh Inactive',
                dotColor: widget.isActive
                    ? AppColors.secondary
                    : const Color(0xFF767964),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = ScreenUtils.fromConstraints(constraints);

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: layout.horizontalPadding,
                    vertical: layout.sectionGap,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _buildProfilePreview(layout)),
                      SizedBox(height: layout.sectionGap),
                      Text(
                        'Your name',
                        style: TextStyle(
                          fontSize: layout.isSmallPhone ? 14 : 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neutral,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        maxLength: 30,
                        textCapitalization: TextCapitalization.words,
                        cursorColor: AppColors.secondary,
                        decoration: InputDecoration(
                          hintText: 'Enter your name',
                          filled: true,
                          fillColor: AppColors.primarySurface,
                          counterText: '',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.secondary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: layout.sectionGap),
                      Text(
                        'Profile picture',
                        style: TextStyle(
                          fontSize: layout.isSmallPhone ? 14 : 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neutral,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Choose an avatar or use a photo from your device.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF767964),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _pickProfileImage,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose a profile photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: const BorderSide(color: AppColors.secondary),
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
                      SizedBox(height: layout.sectionGap * 0.7),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _avatars.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (context, index) {
                          final avatar = _avatars[index];
                          final selected =
                              _imagePath.isEmpty && _avatar == avatar;

                          return GestureDetector(
                            onTap: _isSaving
                                ? null
                                : () => _selectAvatar(avatar),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primarySurface,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.secondary
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipOval(
                                    child: SvgPicture.asset(
                                      avatar,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (selected)
                                    const Align(
                                      alignment: Alignment.bottomRight,
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor: AppColors.secondary,
                                        child: Icon(
                                          Icons.check,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: layout.sectionGap),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.neutral,
                          disabledBackgroundColor: AppColors.primarySurface,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.secondary,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Saving…' : 'Save changes'),
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

  Widget _buildProfilePreview(ScreenUtils screen) {
    final profile = _originalProfile;
    final size = screen.isSmallPhone ? 104.0 : 120.0;
    Widget image;

    if (_imagePath.isNotEmpty) {
      image = Image.file(File(_imagePath), fit: BoxFit.cover);
    } else if (_avatar.isNotEmpty) {
      image = SvgPicture.asset(_avatar, fit: BoxFit.cover);
    } else {
      image = BuildProfileImage(profile: profile);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primarySurface,
            border: Border.all(color: AppColors.primary, width: 4),
          ),
          child: ClipOval(child: image),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              border: Border.all(color: AppColors.background, width: 2),
            ),
            child: const Icon(Icons.edit, size: 18, color: AppColors.neutral),
          ),
        ),
      ],
    );
  }

  void _selectAvatar(String avatar) {
    setState(() {
      _avatar = avatar;
      _imagePath = '';
      _compressedImage = '';
    });
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (image == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final extension = p.extension(image.path).isEmpty
          ? '.jpg'
          : p.extension(image.path);
      final savedPath = p.join(
        directory.path,
        'profile_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      await File(image.path).copy(savedPath);

      final compressedImage = await _compressImage(savedPath);
      if (compressedImage == null) {
        await _deleteImage(savedPath);
        AppHelpers.showErrorSnackbar(
          title: 'Image unavailable',
          message: 'Could not prepare this image. Please choose another photo.',
        );
        return;
      }

      _temporaryImagePaths.add(savedPath);
      setState(() {
        _imagePath = savedPath;
        _compressedImage = compressedImage;
        _avatar = '';
      });
    } catch (error) {
      AppHelpers.showErrorSnackbar(
        title: 'Image unavailable',
        message: 'Could not select a profile photo.',
      );
    }
  }

  Future<String?> _compressImage(String imagePath) async {
    const attempts = <List<int>>[
      [128, 45],
      [96, 35],
      [64, 30],
    ];

    for (final attempt in attempts) {
      final Uint8List? compressed = await FlutterImageCompress.compressWithFile(
        imagePath,
        minWidth: attempt[0],
        minHeight: attempt[0],
        quality: attempt[1],
        format: CompressFormat.jpeg,
      );
      if (compressed == null) return null;

      final encoded = base64Encode(compressed);
      if (encoded.length <= 12000) return encoded;
    }
    return null;
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    final profile = _originalProfile;
    final name = _nameController.text.trim();

    if (profile == null) {
      AppHelpers.showErrorSnackbar(
        title: 'Profile unavailable',
        message: 'Your profile could not be loaded.',
      );
      return;
    }
    if (name.isEmpty) {
      AppHelpers.showErrorSnackbar(
        title: 'Name required',
        message: 'Enter a name before saving your profile.',
      );
      return;
    }
    if (name.runes.length > 30) {
      AppHelpers.showErrorSnackbar(
        title: 'Name too long',
        message: 'Your name can be at most 30 characters.',
      );
      return;
    }
    if (_avatar.isEmpty && _imagePath.isEmpty) {
      AppHelpers.showErrorSnackbar(
        title: 'Picture required',
        message: 'Choose an avatar or a profile photo.',
      );
      return;
    }

    setState(() => _isSaving = true);
    final updatedProfile = UserProfile(
      userId: profile.userId,
      name: name,
      avatar: _avatar,
      imagePath: _imagePath,
      compressedImage: _compressedImage,
    );

    try {
      await Hive.box<UserProfile>('userProfileBox')
          .put('current', updatedProfile);
      _homeController.userProfileData.value = updatedProfile;
      _originalProfile = updatedProfile;

      var meshUpdateFailed = false;
      try {
        await Get.find<MeshNetworkController>().updateLocalProfile(
          updatedProfile,
        );
      } catch (error) {
        meshUpdateFailed = true;
      }

      if (profile.imagePath.isNotEmpty && profile.imagePath != _imagePath) {
        await _deleteImage(profile.imagePath);
      }
      _temporaryImagePaths.remove(_imagePath);
      if (meshUpdateFailed) {
        AppHelpers.showWarningSnackbar(
          title: 'Profile saved',
          message: 'Nearby devices may need a moment to receive your changes.',
        );
      } else {
        AppHelpers.showSuccessSnackbar(
          title: 'Profile updated',
          message: 'Your name and profile picture have been saved.',
        );
      }
    } catch (error) {
      AppHelpers.showErrorSnackbar(
        title: 'Could not save profile',
        message: 'Please try saving your changes again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteImage(String path) async {
    if (path.isEmpty) return;
    try {
      final imageFile = File(path);
      if (await imageFile.exists()) await imageFile.delete();
    } catch (error) {
      return;
    }
  }
}
