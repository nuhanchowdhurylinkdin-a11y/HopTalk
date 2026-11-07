import 'dart:typed_data';

/// Decoded binary LoRa message. ID prefixes are 16 hex characters (8 bytes);
/// [encryptedBody] contains the AES-GCM ciphertext bytes.
/// Wire layout: type (1) + message ID (8) + sender prefix (8) + target prefix (8) + body.
class LoRaPacket {
  final int packetType;
  final String messageId;
  final String senderIdPrefix;
  final String targetIdPrefix;
  final Uint8List encryptedBody;

  const LoRaPacket({
    required this.packetType,
    required this.messageId,
    required this.senderIdPrefix,
    required this.targetIdPrefix,
    required this.encryptedBody,
  });

  /// Packet type constants
  static const int typeMessage = 0x01;

  /// Header size in bytes
  static const int headerSize = 25;

  /// Calculate total packet size
  int get totalSize => headerSize + encryptedBody.length;
}
