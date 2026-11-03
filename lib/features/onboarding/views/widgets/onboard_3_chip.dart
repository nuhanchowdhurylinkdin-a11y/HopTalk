import 'package:flutter/material.dart';
import 'package:hop_talk/core/utils/constants/icon_path.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboarding_chip.dart';

class Onboard3Chip extends StatelessWidget {
  const Onboard3Chip({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        OnboardChip(
          title: "Up to 10+ km range",
          dotColor: AppColors.neutral,
          isIcon: true,
          icon: IconPath.compas,
          height: 32,
          borderRadius: 200,
        ),

        SizedBox(height: 15),

        OnboardChip(
          title: "Ultra-low power radio",
          dotColor: AppColors.neutral,
          isIcon: true,
          icon: IconPath.power,
          height: 32,
          borderRadius: 200,
        ),
      ],
    );
  }
}