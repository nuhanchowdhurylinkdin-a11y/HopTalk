import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/lora_packet.dart';

/// Service for encoding/decoding LoRa binary packets
class LoRaCodec {
  // LoRa limits
  static const int maxLoraPayloadBytes = 200;
  static const int loraHeaderBytes = LoRaPacket.headerSize; // 25 bytes
  static const int aesGcmOverheadBytes = 28; // 12-byte nonce + 16-byte MAC
  static const int maxLoraPlaintextBytes =
      maxLoraPayloadBytes - loraHeaderBytes - aesGcmOverheadBytes; // 147 bytes

  /// Encode a mesh packet to binary LoRa format
  /// Input is a mesh JSON packet. Only the fields needed by LoRa are encoded;
  /// routing metadata such as `ttl`, `hopCount`, and `gw` stays on the mesh.
  /// Output: Uint8List ready to send via BLE to ESP32
  static Uint8List encode(Map<String, dynamic> packet) {
    try {
      final String messageId = packet['messageId'] as String;
      final String senderId = packet['senderId'] as String;
      final String targetId = packet['targetId'] as String;
      final String encryptedBodyBase64 = packet['body'] as String;

      // Decode base64 encrypted body to bytes
      final Uint8List bodyBytes = base64Decode(encryptedBodyBase64);

      // Check size limit
      final int totalSize = loraHeaderBytes + bodyBytes.length;
      if (totalSize > maxLoraPayloadBytes) {
        throw Exception('Packet too large: $totalSize bytes (max $maxLoraPayloadBytes)');
      }

      // Create buffer
      final ByteData buffer = ByteData(totalSize);
      int offset = 0;

      // Byte 0: Packet type
      buffer.setUint8(offset++, LoRaPacket.typeMessage);

      // Bytes 1-8: Message ID (8 bytes from 16 hex chars)
      if (messageId.length != 16) {
        throw Exception('Invalid messageId length: ${messageId.length}, expected 16');
      }
      for (int i = 0; i < 16; i += 2) {
        final int byte = int.parse(messageId.substring(i, i + 2), radix: 16);
        buffer.setUint8(offset++, byte);
      }

      // IDs are 64-character hexadecimal hashes. Store 8 actual bytes
      // (16 hex characters), not 8 UTF-8 characters (only 32 bits).
      _writeIdPrefix(buffer, senderId, offset);
      offset += 8;
      _writeIdPrefix(buffer, targetId, offset);
      offset += 8;

      // Bytes 25-N: Encrypted body
      for (int i = 0; i < bodyBytes.length; i++) {
        buffer.setUint8(offset++, bodyBytes[i]);
      }

      if (kDebugMode) {
        debugPrint('[LoRaCodec] Encoded: header=$loraHeaderBytes + body=${bodyBytes.length} = $totalSize bytes');
      }

      return buffer.buffer.asUint8List();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LoRaCodec] Encode error: $e');
      }
      rethrow;
    }
  }

  /// Decode binary LoRa packet to LoRaPacket model
  /// Input: Uint8List from ESP32 via BLE
  /// Output: LoRaPacket with prefixes (not expanded yet)
  static LoRaPacket? decode(Uint8List bytes) {
    try {
      if (bytes.length < loraHeaderBytes) {
        if (kDebugMode) {
          debugPrint('[LoRaCodec] Packet too short: ${bytes.length} bytes');
        }
        return null;
      }

      final ByteData buffer = ByteData.sublistView(bytes);
      int offset = 0;

      // Byte 0: Packet type
      final int packetType = buffer.getUint8(offset++);
      if (packetType != LoRaPacket.typeMessage) {
        if (kDebugMode) {
          debugPrint('[LoRaCodec] Unknown packet type: $packetType');
        }
        return null;
      }

      // Bytes 1-8: Message ID
      final List<int> msgIdBytes = [];
      for (int i = 0; i < 8; i++) {
        msgIdBytes.add(buffer.getUint8(offset++));
      }
      final String messageId = msgIdBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Bytes 9-16: Sender ID prefix
      final List<int> senderPrefixBytes = [];
      for (int i = 0; i < 8; i++) {
        senderPrefixBytes.add(buffer.getUint8(offset++));
      }
      final String senderPrefix = _bytesToHex(senderPrefixBytes);

      // Bytes 17-24: Target ID prefix
      final List<int> targetPrefixBytes = [];
      for (int i = 0; i < 8; i++) {
        targetPrefixBytes.add(buffer.getUint8(offset++));
      }
      final String targetPrefix = _bytesToHex(targetPrefixBytes);

      // Bytes 25-N: Encrypted body
      final Uint8List bodyBytes = bytes.sublist(offset);

      if (kDebugMode) {
        debugPrint('[LoRaCodec] Decoded: msgId=$messageId, sender=$senderPrefix*, target=$targetPrefix*, body=${bodyBytes.length}b');
      }

      return LoRaPacket(
        packetType: packetType,
        messageId: messageId,
        senderIdPrefix: senderPrefix,
        targetIdPrefix: targetPrefix,
        encryptedBody: bodyBytes,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LoRaCodec] Decode error: $e');
      }
      return null;
    }
  }

  static void _writeIdPrefix(ByteData buffer, String id, int offset) {
    if (id.length < 16 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(id)) {
      throw FormatException('User ID must contain at least 16 hexadecimal characters');
    }
    for (int i = 0; i < 16; i += 2) {
      buffer.setUint8(offset++, int.parse(id.substring(i, i + 2), radix: 16));
    }
  }

  static String _bytesToHex(List<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Generate random 8-byte message ID (16 hex chars)
  static String generateMessageId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Calculate estimated encrypted size for plaintext
  static int estimateEncryptedSize(String plaintext) {
    final int plaintextBytes = utf8.encode(plaintext).length;
    final int encryptedBytes = plaintextBytes + aesGcmOverheadBytes;
    return loraHeaderBytes + encryptedBytes;
  }

  /// Check if message fits in LoRa packet
  static bool canFitInLora(String plaintext) {
    return estimateEncryptedSize(plaintext) <= maxLoraPayloadBytes;
  }
}
