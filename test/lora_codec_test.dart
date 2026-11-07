import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hop_talk/features/mesh_network/models/lora_packet.dart';
import 'package:hop_talk/features/mesh_network/service/lora_codec.dart';

const String _senderId =
    '87bccc34ef58642a4cb3343fdd8d85c3d1cef9854fa980262574ff2d4a30496d';
const String _targetId =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Map<String, dynamic> _packet({required String messageId, required int bodyLen}) {
  final Uint8List body = Uint8List.fromList(
    List<int>.generate(bodyLen, (i) => (i * 7 + 3) & 0xFF),
  );
  return {
    'messageId': messageId,
    'senderId': _senderId,
    'targetId': _targetId,
    'body': base64Encode(body),
  };
}

void main() {
  group('LoRaCodec', () {
    test('round trip keeps messageId, id prefixes and body bytes', () {
      final String messageId = LoRaCodec.generateMessageId();
      final Map<String, dynamic> packet = _packet(
        messageId: messageId,
        bodyLen: 60,
      );

      final Uint8List bytes = LoRaCodec.encode(packet);
      expect(bytes.length, LoRaPacket.headerSize + 60);

      final LoRaPacket? decoded = LoRaCodec.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.packetType, LoRaPacket.typeMessage);
      expect(decoded.messageId, messageId);
      expect(decoded.senderIdPrefix, _senderId.substring(0, 16));
      expect(decoded.targetIdPrefix, _targetId.substring(0, 16));
      expect(base64Encode(decoded.encryptedBody), packet['body']);
    });

    test('generateMessageId returns 16 lowercase hex chars', () {
      final String id = LoRaCodec.generateMessageId();
      expect(id.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), isTrue);
      expect(LoRaCodec.generateMessageId(), isNot(id));
    });

    test('packet of exactly 200 bytes is accepted', () {
      final int bodyLen =
          LoRaCodec.maxLoraPayloadBytes - LoRaPacket.headerSize;
      final Uint8List bytes = LoRaCodec.encode(
        _packet(messageId: '0123456789abcdef', bodyLen: bodyLen),
      );
      expect(bytes.length, LoRaCodec.maxLoraPayloadBytes);
    });

    test('packet over 200 bytes throws', () {
      final int bodyLen =
          LoRaCodec.maxLoraPayloadBytes - LoRaPacket.headerSize + 1;
      expect(
        () => LoRaCodec.encode(
          _packet(messageId: '0123456789abcdef', bodyLen: bodyLen),
        ),
        throwsException,
      );
    });

    test('messageId with wrong length throws', () {
      expect(
        () => LoRaCodec.encode(_packet(messageId: 'abcd', bodyLen: 10)),
        throwsException,
      );
    });

    test('decode returns null for short or unknown packets', () {
      expect(LoRaCodec.decode(Uint8List(10)), isNull);

      final Uint8List bytes = LoRaCodec.encode(
        _packet(messageId: '0123456789abcdef', bodyLen: 20),
      );
      bytes[0] = 0x7F;
      expect(LoRaCodec.decode(bytes), isNull);
    });

    test('147 byte plaintext fits and 148 does not', () {
      expect(LoRaCodec.maxLoraPlaintextBytes, 147);
      expect(LoRaCodec.canFitInLora('a' * 147), isTrue);
      expect(LoRaCodec.canFitInLora('a' * 148), isFalse);
    });

    test('multi-byte text is measured in UTF-8 bytes', () {
      // Each Bengali letter is 3 bytes in UTF-8: 49 * 3 = 147 fits, 50 does not.
      expect(LoRaCodec.canFitInLora('অ' * 49), isTrue);
      expect(LoRaCodec.canFitInLora('অ' * 50), isFalse);
    });
  });
}
