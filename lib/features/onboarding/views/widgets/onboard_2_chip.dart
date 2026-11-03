import 'package:flutter/material.dart';
import 'package:hop_talk/core/utils/constants/icon_path.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/onboarding/views/widgets/onboarding_chip.dart';

class Onboard2Chip extends StatelessWidget {
  const Onboard2Chip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: OnboardChip(
            title: "Hop-by-hop relay",
            dotColor: AppColors.neutral,
            isIcon: true,
            icon: IconPath.hop,
            height: 32,
            borderRadius: 200,
          ),
        ),

        SizedBox(width: 15),

        Expanded(
          child: OnboardChip(
            title: "Zero cellular required",
            dotColor: AppColors.neutral,
            isIcon: true,
            icon: IconPath.network,
            height: 32,
            borderRadius: 200,
          ),
        ),
      ],
    );
  }
}
