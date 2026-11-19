import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/state_manager.dart';
import 'package:get/utils.dart';
import 'package:hop_talk/core/common/widgets/submit_button.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/setup/controller/setup_controller.dart';

class SetupScreen extends GetView<SetupController> {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screen = ScreenUtils.fromConstraints(constraints);

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screen.horizontalPadding,
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: screen.setupTopSpacing),
                          Text(
                            'Set Up Your Profile',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: screen.titleSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: screen.isSmallPhone ? 8 : 10),
                          Text(
                            'Choose how nearby peers recognize you on the mesh network.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: screen.descriptionSize,
                              color: const Color(0xFF454836),
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: screen.sectionGap),
                          _buildProfileImage(screen.profileAvatarSize),
                          SizedBox(height: screen.sectionGap * 0.65),
                          TextField(
                            controller: controller.nameController,
                            textAlign: TextAlign.center,
                            cursorColor: AppColors.neutral,
                            style: TextStyle(
                              fontSize: screen.isSmallPhone ? 16 : 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.neutral,
                            ),
                            decoration: InputDecoration(
                              suffix: Icon(
                                Icons.edit,
                                color: AppColors.neutral.withValues(alpha: 0.6),
                              ),
                              hintText: 'Enter Your Name',
                              hintStyle: TextStyle(
                                fontSize: screen.isSmallPhone ? 18 : 22,
                                color: Colors.grey,
                              ),
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.grey,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.secondary,
                                ),
                              ),
                            ),
                          ).paddingSymmetric(
                            horizontal: screen.isSmallPhone ? 8 : 25,
                          ),
                          SizedBox(height: screen.sectionGap),
                          SizedBox(
                            height: screen.avatarGridHeight,
                            child: PageView.builder(
                              controller: controller.avatarPageController,
                              itemCount: controller.avatarPageCount,
                              onPageChanged: (index) {
                                controller.currentAvatarPage.value = index;
                              },
                              itemBuilder: (context, pageIndex) {
                                final pageAvatars = controller.avatarsForPage(
                                  pageIndex,
                                );

                                return GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: pageAvatars.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 4,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 1,
                                      ),
                                  itemBuilder: (context, index) {
                                    final avatar = pageAvatars[index];

                                    return Obx(() {
                                      final isActive =
                                          controller.selectedAvatar.value ==
                                          avatar;

                                      return GestureDetector(
                                        onTap: () =>
                                            controller.selectAvatar(avatar),
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isActive
                                                  ? AppColors.primary
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
                                              if (isActive)
                                                const Align(
                                                  alignment:
                                                      Alignment.bottomRight,
                                                  child: CircleAvatar(
                                                    radius: 9,
                                                    backgroundColor:
                                                        AppColors.secondary,
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
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          SizedBox(height: screen.isSmallPhone ? 12 : 16),
                          Obx(
                            () => Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                controller.avatarPageCount,
                                (index) {
                                  final isActive =
                                      controller.currentAvatarPage.value ==
                                      index;

                                  return GestureDetector(
                                    onTap: () {
                                      controller.avatarPageController
                                          .animateToPage(
                                            index,
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            curve: Curves.easeInOut,
                                          );
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      width: isActive ? 12 : 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isActive
                                            ? AppColors.secondary
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(height: screen.sectionGap),
                          SubmitButton(
                            title: 'Done',
                            callback: controller.saveProfile,
                          ),
                          SizedBox(height: screen.setupTopSpacing * 0.5),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileImage(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Obx(() {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 6,
                ),
              ),
              child: Container(
                height: size,
                width: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                ),
                child: ClipOval(
                  child: controller.selectedAvatar.isNotEmpty
                      ? SvgPicture.asset(controller.selectedAvatar.value)
                      : controller.profileImagePath.isNotEmpty
                      ? Image.file(
                          File(controller.profileImagePath.value),
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.person),
                ),
              ),
            );
          }),
          Align(
            alignment: Alignment.bottomRight,
            child: Material(
              elevation: 7,
              borderRadius: const BorderRadius.all(Radius.circular(300)),
              child: InkWell(
                onTap: controller.pickImageFromGallery,
                child: Container(
                  height: 32,
                  width: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.camera_alt_outlined, size: 17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
