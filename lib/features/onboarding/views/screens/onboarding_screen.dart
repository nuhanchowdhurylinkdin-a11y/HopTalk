import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/common/widgets/submit_button.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/constants/icon_path.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/onboarding/controller/onboarding_controller.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboard_1_chip.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboard_2_chip.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboard_3_chip.dart';

class OnboardingScreen extends GetView<OnboardingController> {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screen = ScreenUtils.fromConstraints(constraints);

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screen.horizontalPadding,
              ),
              child: Stack(
                children: [
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                  Positioned(
                    top: 46,
                    left: 0,
                    right: 0,
                    bottom: 126,
                    child: PageView.builder(
                      controller: controller.pageController,
                      onPageChanged: controller.updatePageIndicator,
                      itemCount: controller.onboardingPages.length,
                      itemBuilder: (context, index) {
                        final page = controller.onboardingPages[index];
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: screen.imageHeight,
                                width: double.infinity,
                                child: Image.asset(
                                  page.image,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              SizedBox(height: screen.sectionGap * 0.55),
                              if (index == 1) const Onboard2Chip(),
                              if (index == 3) const Onboard3Chip(),
                              if (index == 1 || index == 3)
                                SizedBox(height: screen.sectionGap),
                              Text(
                                page.title,
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  fontSize: screen.titleSize,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.neutral,
                                  height: 1.15,
                                ),
                              ),
                              SizedBox(height: screen.isSmallPhone ? 10 : 14),
                              Text(
                                page.description,
                                style: TextStyle(
                                  fontSize: screen.descriptionSize,
                                  color: const Color(0xFF767964),
                                  height: 1.45,
                                ),
                              ),
                              SizedBox(height: screen.sectionGap),
                              if (index == 0) const Onboard1Chip(),
                              if (index == 2) _buildLoRaFeature(),
                              SizedBox(height: screen.sectionGap),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 74,
                    left: 0,
                    right: 0,
                    child: Obx(
                      () => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          controller.onboardingPages.length,
                          (index) {
                            final isActive =
                                controller.selectedPageIndex.value == index;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(right: 6),
                              height: 8,
                              width: isActive ? 24 : 8,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.neutral
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Obx(
                      () => SubmitButton(
                        title: controller.isLastPage ? 'Get started' : 'Next',
                        callback: controller.forwardAction,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: AppColors.backgroundSecondary,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Obx(
                () => Container(
                  height: 12,
                  width: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: controller.selectedPageIndex.value == 1
                        ? AppColors.tertiary
                        : controller.selectedPageIndex.value == 2
                        ? AppColors.secondary
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Obx(
                () => Text(
                  controller.selectedPageIndex.value == 1
                      ? 'P2P MESH'
                      : controller.selectedPageIndex.value == 2
                      ? 'LORA 915 MHZ'
                      : 'OFFLINE READY',
                  style: const TextStyle(
                    color: AppColors.neutral,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: controller.skipAction,
          child: const Text('SKIP', style: TextStyle(color: Color(0xFF767964))),
        ),
      ],
    );
  }

  Widget _buildLoRaFeature() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      constraints: const BoxConstraints(minHeight: 48),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SvgPicture.asset(IconPath.tower),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Zero Infrastructure',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Point-to-point sub-GHz packet telemetry',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
