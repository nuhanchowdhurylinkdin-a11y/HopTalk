import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../../setup/models/user_profile.dart';

class BuildProfileImage extends StatelessWidget {
  const BuildProfileImage({super.key, required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    if (profile != null && profile!.compressedImage.isNotEmpty) {
      return Image.memory(
        base64Decode(profile!.compressedImage),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.person, size: 32, color: Colors.grey);
        },
      );
    }
    else if (profile!.avatar.isNotEmpty) {
      return SvgPicture.asset(
        profile!.avatar,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
      );
    }
    return const Icon(Icons.person, size: 32, color: Colors.grey);
  }
}
