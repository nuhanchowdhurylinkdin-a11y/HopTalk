import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.avatar = '',
    this.imageByte = '',
  });

  final String peerId;
  final String peerName;
  final String avatar;
  final String imageByte;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MeshNetworkController mesh = Get.find<MeshNetworkController>();
  final TextEditingController _textController = TextEditingController();

  List<Map<String, dynamic>> _conversation() {
    return mesh.chatMessages
        .where((m) {
      final bool isMine = m['isMine'] == true;
      return isMine
          ? m['targetId'] == widget.peerId
          : m['senderId'] == widget.peerId;
    })
        .toList()
        .reversed
        .toList();
  }

  void _send() {
    final String text = _textController.text.trim();
    if (text.isEmpty) return;

    final bool sent = mesh.broadcastMessage(widget.peerId, text, false);

    if (sent) {
      _textController.clear();
    } else {
      Get.snackbar("Not sent", "No connected device, or message is too long.");
    }
  }

  String _time(int millis) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(millis);
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.transparent,
              child: ClipOval(
                child: BuildProfileImage(
                  profile: UserProfile(
                    userId: widget.peerId,
                    name: widget.peerName,
                    avatar: widget.avatar,
                    imagePath: '',
                    compressedImage: widget.imageByte,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.peerName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              final messages = _conversation();

              if (messages.isEmpty) {
                return const Center(child: Text("No messages yet"));
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final m = messages[index];
                  final bool isMine = m['isMine'] == true;

                  return Align(
                    alignment:
                    isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isMine
                            ? const Color(0xFF0053DB)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            m['body'] as String,
                            style: TextStyle(
                              color: isMine ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _time(m['timestamp'] as int),
                            style: TextStyle(
                              fontSize: 10,
                              color: isMine ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: "Message",
                        counterText: '',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF0053DB),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}