import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/features/chat/controller/chat_controller.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
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
  late final ChatController controller;
  bool _forceLora = false;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      ChatController(peerId: widget.peerId),
      tag: widget.peerId,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    Get.delete<ChatController>(tag: widget.peerId);
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _textController.text;
    if (text.trim().isEmpty) return;

    final bool sent = await controller.send(text, forceLora: _forceLora);

    if (sent) {
      _textController.clear();
    } else {
      Get.snackbar(
        "Not sent",
        "No connection, the other user's key has not arrived yet, or the message is too long.",
      );
    }
  }

  String _time(int millis) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(millis);
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return "$h:$m";
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
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Force LoRa (test)',
              icon: Icon(
                Icons.cell_tower,
                color: _forceLora ? Colors.orange : null,
              ),
              onPressed: () => setState(() => _forceLora = !_forceLora),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              if (controller.isInitialLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final messages = controller.messages;
              final bool showLoader = controller.hasMore.value;

              if (messages.isEmpty) {
                return const Center(child: Text("No messages yet"));
              }

              return ListView.builder(
                controller: controller.scrollController,
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length + (showLoader ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= messages.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }

                  final message = messages[index];
                  final bool isMine = controller.isMine(message);

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
                            message.body,
                            style: TextStyle(
                              color: isMine ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _time(message.timestamp),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMine
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                              if (isMine) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  message.seen ? Icons.done_all : Icons.done,
                                  size: 14,
                                  color: message.seen
                                      ? Colors.lightBlueAccent
                                      : Colors.white70,
                                ),
                              ],
                            ],
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