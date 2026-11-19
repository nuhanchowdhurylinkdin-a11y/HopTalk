import 'package:flutter/widgets.dart';

class ScreenUtils {
  const ScreenUtils({required this.width, required this.height});

  final double width;
  final double height;

  factory ScreenUtils.fromConstraints(BoxConstraints constraints) {
    return ScreenUtils(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
    );
  }

  factory ScreenUtils.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ScreenUtils(width: size.width, height: size.height);
  }

  bool get isSmallPhone => height < 700 || width < 360;
  bool get isLargePhone => height >= 850 && width >= 390;

  double get horizontalPadding => width < 360 ? 16 : 20;
  double get imageHeight {
    final fraction = isSmallPhone
        ? 0.34
        : isLargePhone
        ? 0.43
        : 0.39;
    return (height * fraction).clamp(190, 390).toDouble();
  }

  double get titleSize => isSmallPhone
      ? 28
      : isLargePhone
      ? 36
      : 32;
  double get descriptionSize => isSmallPhone ? 14 : 16;
  double get sectionGap => isSmallPhone
      ? 16
      : isLargePhone
      ? 28
      : 22;

  double get setupTopSpacing => isSmallPhone
      ? 24
      : isLargePhone
      ? 40
      : 32;

  double get profileAvatarSize => isSmallPhone
      ? 88
      : isLargePhone
      ? 112
      : 96;

  double get avatarGridHeight {
    final itemSize = (width - 60) / 4;
    return itemSize * 2 + 48;
  }
}
