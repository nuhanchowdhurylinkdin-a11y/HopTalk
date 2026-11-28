import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hop_talk/features/mesh_network/service/esp_flasher.dart';

void main() {
  group('SLIP frames', () {
    test('encodes and decodes reserved bytes', () {
      final Uint8List input = Uint8List.fromList([0x01, 0xC0, 0xDB, 0x02]);
      expect(SlipCodec.decodeFrame(SlipCodec.encodeFrame(input)), input);
    });

    test('decodes frames split across input chunks', () {
      final Uint8List encoded = SlipCodec.encodeFrame([0x11, 0x22]);
      final SlipFrameDecoder decoder = SlipFrameDecoder();

      expect(decoder.add(encoded.sublist(0, 2)), isEmpty);
      expect(decoder.add(encoded.sublist(2)), [
        Uint8List.fromList([0x11, 0x22]),
      ]);
    });
  });

  test('builds ROM commands with little-endian header and checksum', () {
    final Uint8List encoded = EspLoaderProtocol.buildCommand(0x03, [
      0xAA,
      0xBB,
    ], checksum: 0xCC);
    final Uint8List packet = SlipCodec.decodeFrame(encoded);
    final ByteData header = ByteData.sublistView(packet);

    expect(packet[0], 0x00);
    expect(packet[1], 0x03);
    expect(header.getUint16(2, Endian.little), 2);
    expect(header.getUint32(4, Endian.little), 0xCC);
    expect(packet.sublist(8), [0xAA, 0xBB]);
    expect(EspLoaderProtocol.checksum([0xAA, 0xBB]), 0xEF ^ 0xAA ^ 0xBB);
  });

  test('configures the detected 4 MiB flash size', () {
    final Uint8List parameters = EspLoaderProtocol.flashParameters();
    final ByteData data = ByteData.sublistView(parameters);

    expect(data.getUint32(0, Endian.little), 0);
    expect(data.getUint32(4, Endian.little), 0x400000);
    expect(data.getUint32(8, Endian.little), 0x10000);
    expect(data.getUint32(12, Endian.little), 0x1000);
    expect(data.getUint32(16, Endian.little), 0x100);
    expect(data.getUint32(20, Endian.little), 0xFFFF);
  });

  test('trims trailing FF and rounds image length to a flash sector', () {
    final Uint8List image = Uint8List(0x1003)
      ..fillRange(0, 0x1000, 0x12)
      ..fillRange(0x1000, 0x1003, 0xFF);
    final Uint8List trimmed = EspFlasher.trimFirmware(image);

    expect(trimmed.length, 0x1000);
    expect(trimmed.last, 0x12);
  });

  test('parses ROM MD5 response and excludes status bytes', () {
    final List<int> digest = '0123456789abcdef0123456789abcdef'.codeUnits;
    final Uint8List response = Uint8List(8 + digest.length + 4);
    final ByteData header = ByteData.sublistView(response);
    response[0] = 0x01;
    response[1] = 0x13;
    header.setUint16(2, digest.length + 4, Endian.little);
    response.setRange(8, 8 + digest.length, digest);

    final EspLoaderResponse parsed = EspLoaderProtocol.parseResponse(response);
    expect(parsed.status, 0);
    expect(
      String.fromCharCodes(parsed.resultData),
      '0123456789abcdef0123456789abcdef',
    );
  });
}
