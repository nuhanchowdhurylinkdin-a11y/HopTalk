import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:hop_talk/core/utils/constants/icon_path.dart';

class OnboardChip extends StatelessWidget {
  const OnboardChip({
    super.key,
    required this.title,
    required this.dotColor,
    this.textColor = const Color(0xFF222222),
    this.backgroundColor = const Color(0xFFF6F3F5),
    this.height = 48.0,
    this.isIcon = false,
    this.icon,
    this.borderRadius = 10
  });

  final String title;
  final Color dotColor;
  final Color textColor;
  final Color backgroundColor;
  final double height;
  final bool isIcon;
  final String? icon;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: backgroundColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isIcon)
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          if (isIcon) SvgPicture.asset(icon!),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
