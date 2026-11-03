import 'package:hive/hive.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 1)
class ChatMessage {
  @HiveField(0)
  final String messageId;

  @HiveField(1)
  final String senderId;

  @HiveField(2)
  final String targetId;

  @HiveField(3)
  final String body;

  @HiveField(4)
  final int timestamp;

  @HiveField(5, defaultValue: 0)
  final int hopCount;

  // Outgoing message: the other person has seen it.
  // Incoming message: a "seen" receipt was sent for it.
  @HiveField(6, defaultValue: false)
  final bool seen;

  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.targetId,
    required this.body,
    required this.timestamp,
    this.hopCount = 0,
    this.seen = false,
  });

  ChatMessage copyWith({bool? seen}) {
    return ChatMessage(
      messageId: messageId,
      senderId: senderId,
      targetId: targetId,
      body: body,
      timestamp: timestamp,
      hopCount: hopCount,
      seen: seen ?? this.seen,
    );
  }
}