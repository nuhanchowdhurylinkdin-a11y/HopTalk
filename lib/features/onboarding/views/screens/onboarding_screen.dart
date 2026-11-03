import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/icon_path.dart';
import 'package:hop_talk/core/common/widgets/submit_button.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/onboarding/controller/onboarding_controller.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboard_1_chip.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboard_2_chip.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboard_3_chip.dart';

class OnboardingScreen extends GetView<OnboardingController> {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: controller.pageController,
            onPageChanged: controller.updatePageIndicator,
            itemCount: controller.onboardingPages.length,
            itemBuilder: (context, index) {
              final page = controller.onboardingPages[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(page.image, fit: BoxFit.cover),
                  SizedBox(height: 20),
                  if (index == 1) Onboard2Chip(),
                  if (index == 3) Onboard3Chip(),
                  SizedBox(height: 35),
                  Text(
                    page.title,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutral,
                      height: 1.2,
                    ),
                  ),

                  SizedBox(height: 15),
                  Text(
                    page.description,
                    style: TextStyle(fontSize: 16, color: Color(0xFF767964)),
                  ),

                  SizedBox(height: 25),

                  // Onboarding 1 box
                  if (index == 0) Onboard1Chip(),
                  if (index == 2)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      height: 48,
                      width: double.maxFinite,
                      decoration: BoxDecoration(
                        color: Color(0xFFF6F3F5),
                        borderRadius: BorderRadius.circular(8),
                      ),

                      child: Row(
                        children: [
                          SvgPicture.asset(IconPath.tower),

                          SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Zero Infrastructure',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Point-to-point sub-GHz packet telemetry',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ).marginOnly(top: 150),

          // top section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: AppColors.backgroundSecondary,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Obx(
                      () {
                        return Container(
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
                        );
                      }
                    ),

                    SizedBox(width: 10),
                    Obx(() {
                      return Text(
                        controller.selectedPageIndex.value == 1
                            ? 'P2P MESH'
                            : controller.selectedPageIndex.value == 2
                            ? 'LORA 915 MHZ'
                            : "OFFLINE READY",
                        style: TextStyle(
                          color: AppColors.neutral,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }),
                  ],
                ),
              ),

              TextButton(
                onPressed: controller.skipAction,
                child: Text('SKIP', style: TextStyle(color: Color(0xFF767964))),
              ),
            ],
          ).marginOnly(top: 10),

          // indicator
          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(controller.onboardingPages.length, (
                int index,
              ) {
                bool isActive = controller.selectedPageIndex.value == index;
                return Obx(() {
                  bool isActive = controller.selectedPageIndex.value == index;
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
                });
              }),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Obx(
              () {
                return SubmitButton(
                  title: controller.isLastPage ? "Get started" : "Next",
                  callback: controller.forwardAction,
                );
              }
            ),
          ),
        ],
      ).marginSymmetric(horizontal: 16, vertical: 16),
    );
  }
}
