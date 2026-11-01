
import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  final String userId;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String avatar;

  @HiveField(3)
  final String imagePath;

  @HiveField(4, defaultValue: '')
  final String compressedImage;

  UserProfile({
    required this.userId,
    required this.name,
    required this.avatar,
    required this.imagePath,
    required this.compressedImage,
  });
}
