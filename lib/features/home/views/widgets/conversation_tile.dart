import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/features/chat/views/screens/chat_screen.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.mesh,
  });

  final Map<String, dynamic> conversation;
  final MeshNetworkController mesh;

  String _formatTime(int millis) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(millis);
    final DateTime now = DateTime.now();

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    if (sameDay(t, now)) {
      final String h = t.hour.toString().padLeft(2, '0');
      final String m = t.minute.toString().padLeft(2, '0');
      return "$h:$m";
    }

    if (sameDay(t, now.subtract(const Duration(days: 1)))) {
      return "Yesterday";
    }

    final String d = t.day.toString().padLeft(2, '0');
    final String mo = t.month.toString().padLeft(2, '0');
    return "$d/$mo/${t.year}";
  }

  @override
  Widget build(BuildContext context) {
    final String peerId = conversation['peerId'] as String;
    final String savedName = (conversation['peerName'] as String?) ?? '';
    final String name = savedName.isNotEmpty
        ? savedName
        : (peerId.length > 6 ? peerId.substring(0, 6) : peerId);
    final String avatar = (conversation['avatar'] as String?) ?? '';
    final String image = (conversation['image'] as String?) ?? '';
    final String lastBody = (conversation['lastBody'] as String?) ?? '';
    final int lastTimestamp = (conversation['lastTimestamp'] as int?) ?? 0;
    final bool lastIsMine = conversation['lastIsMine'] == true;
    final bool lastSeen = conversation['lastMessageSeen'] == true;
    final int unread = (conversation['unreadCount'] as int?) ?? 0;

    final route = mesh.routingTable[peerId];
    final bool isOnline = route != null && route.nextHopId != 'SELF';

    final TextStyle? subtitleStyle = unread > 0
        ? const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)
        : const TextStyle(color: Colors.black54);

    Widget subtitle;
    if (lastBody.isEmpty) {
      final String status = !isOnline
          ? "Offline"
          : (route.hopCount == 1 ? "Connected" : "${route.hopCount} hops away");
      subtitle = Text(status, style: const TextStyle(color: Colors.black54));
    } else {
      subtitle = Row(
        children: [
          if (lastIsMine) ...[
            Icon(
              lastSeen ? Icons.done_all : Icons.done,
              size: 16,
              color: lastSeen ? const Color(0xFF0053DB) : Colors.black45,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              lastBody,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ),
        ],
      );
    }

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.transparent,
            child: ClipOval(
              child: BuildProfileImage(
                profile: UserProfile(
                  userId: peerId,
                  name: name,
                  avatar: avatar,
                  imagePath: '',
                  compressedImage: image,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: subtitle,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastTimestamp > 0)
            Text(
              _formatTime(lastTimestamp),
              style: TextStyle(
                fontSize: 12,
                color: unread > 0 ? AppColors.tertiary : Colors.black45,
              ),
            ),
          if (unread > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                // borderRadius: BorderRadius.circular(10),
                shape: BoxShape.circle
              ),
              child: Text(
                unread > 99 ? "99+" : "$unread",
                style: TextStyle(color: AppColors.neutral, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
      onTap: () => Get.to(
        () => ChatScreen(
          peerId: peerId,
          peerName: name,
          avatar: avatar,
          imageByte: image,
        ),
      ),
    );
  }
}
