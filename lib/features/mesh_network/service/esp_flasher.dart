import 'dart:async';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';

const int kFlashOffset = 0x0;
const int kBlockSize = 0x400;
const int kBaudRate = 115200;
const int kFastBaudRate = 460800;
const int kFlashSize = 0x400000;
const bool kTrimTrailingFF = true;
const String firmwareAssetPath = 'assets/firmware/firmware_merged.bin';

const int _syncOpcode = 0x08;
const int _flashBeginOpcode = 0x02;
const int _flashDataOpcode = 0x03;
const int _flashEndOpcode = 0x04;
const int _spiSetParamsOpcode = 0x0B;
const int _spiAttachOpcode = 0x0D;
const int _changeBaudRateOpcode = 0x0F;
const int _spiFlashMd5Opcode = 0x13;

enum FlashStage {
  findingDevice,
  requestingPermission,
  connecting,
  enteringBootloader,
  syncing,
  preparingFlash,
  writing,
  finishing,
  done,
  failed,
}

class FlashEvent {
  const FlashEvent({
    required this.stage,
    required this.progress,
    required this.message,
    this.error,
  });

  final FlashStage stage;
  final double progress;
  final String message;
  final FlashException? error;
}

class FlashException implements Exception {
  const FlashException(
    this.stage,
    this.message, {
    this.code,
    this.details,
    this.isTimeout = false,
    this.isDisconnected = false,
  });

  final FlashStage stage;
  final String message;
  final int? code;
  final String? details;
  final bool isTimeout;
  final bool isDisconnected;

  @override
  String toString() => message;
}

class FirmwareImageInfo {
  const FirmwareImageInfo({
    required this.originalSize,
    required this.flashSize,
  });

  final int originalSize;
  final int flashSize;
}

class EspLoaderResponse {
  const EspLoaderResponse({
    required this.opcode,
    required this.value,
    required this.data,
    required this.status,
    required this.errorCode,
    required this.statusLength,
  });

  final int opcode;
  final int value;
  final Uint8List data;
  final int? status;
  final int? errorCode;
  final int statusLength;

  Uint8List get resultData {
    if (status == null) return data;
    return Uint8List.sublistView(data, 0, data.length - statusLength);
  }
}

class SlipCodec {
  const SlipCodec._();

  static Uint8List encodeFrame(List<int> payload) {
    final List<int> encoded = [0xC0];
    for (final int byte in payload) {
      if (byte == 0xC0) {
        encoded
          ..add(0xDB)
          ..add(0xDC);
      } else if (byte == 0xDB) {
        encoded
          ..add(0xDB)
          ..add(0xDD);
      } else {
        encoded.add(byte & 0xFF);
      }
    }
    encoded.add(0xC0);
    return Uint8List.fromList(encoded);
  }

  static Uint8List decodeFrame(List<int> frame) {
    int start = 0;
    int end = frame.length;
    if (start < end && frame[start] == 0xC0) start++;
    if (start < end && frame[end - 1] == 0xC0) end--;

    final List<int> decoded = [];
    for (int i = start; i < end; i++) {
      final int byte = frame[i];
      if (byte != 0xDB) {
        decoded.add(byte);
        continue;
      }
      if (++i >= end) throw const FormatException('Incomplete SLIP escape');
      if (frame[i] == 0xDC) {
        decoded.add(0xC0);
      } else if (frame[i] == 0xDD) {
        decoded.add(0xDB);
      } else {
        throw const FormatException('Invalid SLIP escape');
      }
    }
    return Uint8List.fromList(decoded);
  }

  static Uint8List? tryDecodeFrame(List<int> frame) {
    try {
      return decodeFrame(frame);
    } on FormatException {
      return null;
    }
  }
}

class SlipFrameDecoder {
  final List<int> _frame = [];
  bool _insideFrame = false;

  void reset() {
    _frame.clear();
    _insideFrame = false;
  }

  List<Uint8List> add(List<int> bytes) {
    final List<Uint8List> frames = [];
    for (final int byte in bytes) {
      if (byte == 0xC0) {
        if (_insideFrame && _frame.isNotEmpty) {
          final Uint8List? decoded = SlipCodec.tryDecodeFrame(_frame);
          if (decoded != null) frames.add(decoded);
        }
        _frame.clear();
        _insideFrame = true;
      } else if (_insideFrame) {
        _frame.add(byte);
      }
    }
    return frames;
  }
}

class EspLoaderProtocol {
  const EspLoaderProtocol._();

  static int checksum(List<int> bytes) {
    int value = 0xEF;
    for (final int byte in bytes) {
      value ^= byte;
    }
    return value & 0xFF;
  }

  static Uint8List buildCommand(
    int opcode,
    List<int> data, {
    int checksum = 0,
  }) {
    if (data.length > 0xFFFF) {
      throw ArgumentError.value(data.length, 'data.length', 'Too large');
    }
    final Uint8List packet = Uint8List(8 + data.length);
    final ByteData header = ByteData.sublistView(packet);
    packet[0] = 0x00;
    packet[1] = opcode & 0xFF;
    header.setUint16(2, data.length, Endian.little);
    header.setUint32(4, checksum & 0xFF, Endian.little);
    packet.setRange(8, packet.length, data);
    return SlipCodec.encodeFrame(packet);
  }

  static EspLoaderResponse parseResponse(List<int> frame) {
    if (frame.length < 8) {
      throw const FormatException('Response header is incomplete');
    }
    if (frame[0] != 0x01) {
      throw const FormatException('Response direction is invalid');
    }

    final ByteData data = ByteData.sublistView(Uint8List.fromList(frame));
    final int length = data.getUint16(2, Endian.little);
    if (frame.length != 8 + length) {
      throw const FormatException('Response length does not match its header');
    }

    final int opcode = frame[1];
    final Uint8List responseData = Uint8List.fromList(frame.sublist(8));
    final int statusLength = _statusLength(opcode, responseData.length);
    int? status;
    int? errorCode;
    if (statusLength > 0) {
      final int statusIndex = responseData.length - statusLength;
      status = responseData[statusIndex];
      errorCode = responseData[statusIndex + 1];
    }

    return EspLoaderResponse(
      opcode: opcode,
      value: data.getUint32(4, Endian.little),
      data: responseData,
      status: status,
      errorCode: errorCode,
      statusLength: statusLength,
    );
  }

  static int _statusLength(int opcode, int dataLength) {
    if (opcode == _spiFlashMd5Opcode) {
      if (dataLength >= 36) return 4;
      if (dataLength >= 34) return 2;
    }
    if (dataLength >= 4) return 4;
    if (dataLength >= 2) return 2;
    return 0;
  }

  static Uint8List uint32Words(List<int> words) {
    final Uint8List bytes = Uint8List(words.length * 4);
    final ByteData data = ByteData.sublistView(bytes);
    for (int i = 0; i < words.length; i++) {
      data.setUint32(i * 4, words[i], Endian.little);
    }
    return bytes;
  }

  static Uint8List flashParameters({int flashSize = kFlashSize}) {
    return uint32Words([0, flashSize, 64 * 1024, 0x1000, 256, 0xFFFF]);
  }

  static String errorMessage(int code) {
    const Map<int, String> messages = {
      0x05: 'Invalid message format',
      0x06: 'ROM command ran but the requested operation failed',
      0x07: 'Invalid checksum',
      0x08: 'Flash write error',
      0x09: 'Flash read error',
      0x0A: 'Flash read length error',
      0x0B: 'Flash decompression error',
    };
    return messages[code] ??
        'ESP32 error 0x${code.toRadixString(16).padLeft(2, '0')}';
  }
}

class EspFlasher {
  EspFlasher();

  final List<String> logs = [];
  final SlipFrameDecoder _decoder = SlipFrameDecoder();

  StreamController<FlashEvent>? _events;
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<UsbEvent>? _usbSubscription;
  Completer<EspLoaderResponse>? _pendingResponse;
  UsbPort? _port;
  UsbDevice? _device;
  FlashStage _currentStage = FlashStage.findingDevice;
  bool _running = false;
  bool _cancelRequested = false;
  bool _usbDisconnected = false;
  int _fastModeFailureCount = 0;
  double _progress = 0;

  String? get deviceName {
    final UsbDevice? device = _device;
    if (device == null) return null;
    return device.productName?.trim().isNotEmpty == true
        ? device.productName!
        : device.deviceName;
  }

  static Uint8List trimFirmware(Uint8List image) {
    if (!kTrimTrailingFF) return Uint8List.fromList(image);
    int end = image.length;
    while (end > 0 && image[end - 1] == 0xFF) {
      end--;
    }
    if (end == 0) throw const FormatException('Firmware image is empty');
    final int alignedLength = (end + 0xFFF) & ~0xFFF;
    final Uint8List result = Uint8List(alignedLength)
      ..fillRange(0, alignedLength, 0xFF);
    result.setRange(0, end, image);
    return result;
  }

  static Duration estimateDuration({
    required int imageSize,
    required int baudRate,
    bool eraseAllFlash = false,
  }) {
    final int bytes = imageSize + (eraseAllFlash ? kFlashSize : 0);
    final double seconds =
        bytes * 10 / baudRate * 1.35 + (eraseAllFlash ? 20 : 8);
    return Duration(seconds: seconds.ceil());
  }

  static String formatSize(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';

  Stream<FlashEvent> flash({bool eraseAllFlash = false}) {
    if (_running) {
      return Stream<FlashEvent>.error(
        StateError('A firmware flash is already running.'),
      );
    }
    _running = true;
    _cancelRequested = false;
    _usbDisconnected = false;
    _progress = 0;
    logs.clear();
    _events = StreamController<FlashEvent>();
    final Stream<FlashEvent> stream = _events!.stream;
    scheduleMicrotask(() => _run(eraseAllFlash: eraseAllFlash));
    return stream;
  }

  void cancel() {
    if (!_running) return;
    _cancelRequested = true;
    final Completer<EspLoaderResponse>? pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const FlashException(FlashStage.failed, 'Flashing was cancelled.'),
      );
    }
  }

  Future<void> _run({required bool eraseAllFlash}) async {
    try {
      _stage(FlashStage.findingDevice, 'Loading firmware image...');
      final Uint8List image = await _loadFirmware();
      final Uint8List flashImage = trimFirmware(image);
      _log(
        'Firmware image: ${formatSize(image.length)} source, '
        '${formatSize(flashImage.length)} to flash at 0x${kFlashOffset.toRadixString(16)}.',
      );

      _stage(FlashStage.findingDevice, 'Looking for an ESP32 over USB...');
      final List<UsbDevice> devices = await UsbSerial.listDevices();
      final UsbDevice? device = _findEsp32Device(devices);
      if (device == null) {
        throw const FlashException(
          FlashStage.findingDevice,
          'No USB device found. Check OTG cable/adapter and that the cable supports data (not charge-only).',
        );
      }
      _device = device;
      _log(
        'USB device: ${deviceName ?? device.deviceName}; ${_formatVidPid(device)}',
      );

      _stage(FlashStage.requestingPermission, 'Requesting USB permission...');
      _port = await device.create();
      if (_port == null) {
        throw const FlashException(
          FlashStage.requestingPermission,
          'USB permission denied or device could not be opened.',
        );
      }

      _stage(FlashStage.connecting, 'Opening USB serial connection...');
      if (!await _port!.open()) {
        throw const FlashException(
          FlashStage.connecting,
          'USB permission denied or device could not be opened.',
        );
      }
      await _port!.setPortParameters(
        kBaudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      _listenForUsbData();
      _listenForDetach();

      await _resetAndSync();

      bool useFastBaud = false;
      if (_fastModeFailureCount < 2) {
        try {
          _stage(FlashStage.syncing, 'Switching to $kFastBaudRate baud...');
          await _transact(
            _changeBaudRateOpcode,
            EspLoaderProtocol.uint32Words([kFastBaudRate, 0]),
            timeout: const Duration(seconds: 3),
          );
          await _port!.setPortParameters(
            kFastBaudRate,
            UsbPort.DATABITS_8,
            UsbPort.STOPBITS_1,
            UsbPort.PARITY_NONE,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await _flushInput();
          useFastBaud = true;
          _log('Serial speed changed to $kFastBaudRate baud.');
        } on FlashException catch (error) {
          if (error.isDisconnected || _cancelRequested) rethrow;
          _fastModeFailureCount++;
          _log('Fast baud switch failed: ${error.message}');
          await _returnToSafeBaudAndSync();
          _log('Continuing at safe baud rate $kBaudRate.');
        } catch (error) {
          if (_cancelRequested || _usbDisconnected) rethrow;
          _fastModeFailureCount++;
          _log('Fast baud switch failed: $error');
          await _returnToSafeBaudAndSync();
          _log('Continuing at safe baud rate $kBaudRate.');
        }
      } else {
        _log('Fast mode failed twice earlier; using $kBaudRate baud.');
      }

      try {
        await _writeAndVerify(flashImage, eraseAllFlash: eraseAllFlash);
      } on FlashException catch (error) {
        if (!useFastBaud || !error.isTimeout || error.isDisconnected) rethrow;
        _fastModeFailureCount++;
        _log('Fast mode command timed out: ${error.message}');
        await _returnToSafeBaudAndSync();
        _log('Restarting the write at $kBaudRate baud.');
        await _writeAndVerify(flashImage, eraseAllFlash: eraseAllFlash);
      }

      _stage(FlashStage.finishing, 'Rebooting the ESP32...');
      try {
        await _transact(
          _flashEndOpcode,
          EspLoaderProtocol.uint32Words([0]),
          timeout: const Duration(seconds: 2),
        );
      } on FlashException {
        if (_cancelRequested) rethrow;
        _log('ESP32 rebooted without a FLASH_END response.');
      } catch (error) {
        if (_cancelRequested) rethrow;
        _log('ESP32 rebooted without a FLASH_END response: $error');
      }
      _progress = 1;
      if (_fastModeFailureCount >= 2) {
        _log('Fast mode failed twice; safe baud remains the default.');
      } else if (useFastBaud) {
        _fastModeFailureCount = 0;
      }
      _stage(FlashStage.done, 'Verified. Firmware flashed successfully.');
    } on FlashException catch (error) {
      _log('Failed at ${_stageName(error.stage)}: ${error.message}');
      if (error.code != null) {
        _log(
          'ESP32 error code: 0x${error.code!.toRadixString(16).padLeft(2, '0')}',
        );
      }
      _emit(
        FlashEvent(
          stage: FlashStage.failed,
          progress: _progress,
          message: error.message,
          error: error,
        ),
      );
    } catch (error) {
      final FlashException failure = FlashException(
        _currentStage,
        error.toString(),
        details: error.runtimeType.toString(),
      );
      _log('Failed at ${_stageName(failure.stage)}: ${failure.message}');
      _emit(
        FlashEvent(
          stage: FlashStage.failed,
          progress: _progress,
          message: failure.message,
          error: failure,
        ),
      );
    } finally {
      await _cleanup();
      _running = false;
      await _events?.close();
    }
  }

  Future<Uint8List> _loadFirmware() async {
    try {
      final ByteData data = await rootBundle.load(firmwareAssetPath);
      if (data.lengthInBytes == 0) {
        throw const FormatException('Firmware image is empty');
      }
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (error) {
      throw FlashException(
        FlashStage.findingDevice,
        'Firmware file not found in app.',
        details: error.toString(),
      );
    }
  }

  UsbDevice? _findEsp32Device(List<UsbDevice> devices) {
    for (final UsbDevice device in devices) {
      final int? vendorId = device.vid;
      final int? productId = device.pid;
      if (vendorId == 4292 && productId == 60000) return device;
      if (vendorId == 6790 && (productId == 29987 || productId == 21795)) {
        return device;
      }
      if (vendorId == 1027 && productId == 24577) return device;
      if (vendorId == 12346) return device;
    }
    return null;
  }

  String _formatVidPid(UsbDevice device) {
    final String vid = (device.vid ?? 0).toRadixString(16).padLeft(4, '0');
    final String pid = (device.pid ?? 0).toRadixString(16).padLeft(4, '0');
    return 'VID:PID $vid:$pid';
  }

  void _listenForUsbData() {
    final Stream<Uint8List>? input = _port?.inputStream;
    if (input == null) {
      throw const FlashException(
        FlashStage.connecting,
        'USB serial input stream could not be opened.',
      );
    }
    _inputSubscription = input.listen(
      _handleInput,
      onError: (Object error) {
        _failPending(
          FlashException(
            _currentStage,
            'USB disconnected during flashing',
            details: error.toString(),
            isDisconnected: true,
          ),
        );
      },
      onDone: () {
        if (_running && !_cancelRequested) {
          _usbDisconnected = true;
          _failPending(
            const FlashException(
              FlashStage.failed,
              'USB disconnected during flashing',
              isDisconnected: true,
            ),
          );
        }
      },
      cancelOnError: false,
    );
  }

  void _listenForDetach() {
    _usbSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      if (event.event != UsbEvent.ACTION_USB_DETACHED) return;
      final UsbDevice? detached = event.device;
      final UsbDevice? connected = _device;
      if (detached == null || connected == null) return;
      final bool sameDevice =
          detached.deviceId == connected.deviceId ||
          detached.deviceName == connected.deviceName;
      if (!sameDevice) return;
      _usbDisconnected = true;
      _failPending(
        const FlashException(
          FlashStage.failed,
          'USB disconnected during flashing',
          isDisconnected: true,
        ),
      );
    });
  }

  void _handleInput(Uint8List bytes) {
    for (final Uint8List frame in _decoder.add(bytes)) {
      try {
        final EspLoaderResponse response = EspLoaderProtocol.parseResponse(
          frame,
        );
        final Completer<EspLoaderResponse>? pending = _pendingResponse;
        if (pending != null &&
            !pending.isCompleted &&
            response.opcode == _pendingOpcode) {
          pending.complete(response);
        }
      } on FormatException catch (error) {
        _log('Ignored malformed USB response: ${error.message}');
      }
    }
  }

  int? _pendingOpcode;

  Future<EspLoaderResponse> _transact(
    int opcode,
    List<int> data, {
    Duration timeout = const Duration(seconds: 3),
    int checksum = 0,
    FlashStage? stage,
  }) async {
    _checkActive(stage ?? _currentStage);
    final UsbPort? port = _port;
    if (port == null) {
      throw FlashException(
        stage ?? _currentStage,
        'USB serial port is closed.',
      );
    }
    if (_pendingResponse != null) {
      throw StateError('Only one ROM command may be in flight.');
    }

    final Completer<EspLoaderResponse> pending = Completer<EspLoaderResponse>();
    _pendingResponse = pending;
    _pendingOpcode = opcode;
    try {
      await port.write(
        EspLoaderProtocol.buildCommand(opcode, data, checksum: checksum),
      );
      final EspLoaderResponse response = await pending.future.timeout(timeout);
      try {
        _checkResponse(response, stage ?? _currentStage);
      } on FlashException catch (error) {
        _log(
          'ROM command 0x${opcode.toRadixString(16).padLeft(2, '0')} failed: ${error.message}',
        );
        rethrow;
      }
      return response;
    } on TimeoutException {
      throw FlashException(
        stage ?? _currentStage,
        'ESP32 command 0x${opcode.toRadixString(16).padLeft(2, '0')} timed out.',
        isTimeout: true,
      );
    } finally {
      if (identical(_pendingResponse, pending)) {
        _pendingResponse = null;
        _pendingOpcode = null;
      }
    }
  }

  void _checkResponse(EspLoaderResponse response, FlashStage stage) {
    final int? status = response.status;
    if (status != null && status != 0) {
      final int code = response.errorCode ?? 0;
      throw FlashException(
        stage,
        EspLoaderProtocol.errorMessage(code),
        code: code,
      );
    }
  }

  Future<void> _resetAndSync() async {
    FlashException? lastError;
    for (int cycle = 0; cycle < 3; cycle++) {
      _checkActive(FlashStage.enteringBootloader);
      _stage(
        FlashStage.enteringBootloader,
        cycle == 0
            ? 'Entering ESP32 bootloader...'
            : 'Retrying bootloader reset (${cycle + 1}/3)...',
      );
      try {
        await _resetBoard(alternateTiming: cycle > 0);
        _stage(FlashStage.syncing, 'Syncing with ESP32...');
        for (int attempt = 0; attempt < 10; attempt++) {
          try {
            await _flushInput();
            final EspLoaderResponse response = await _transact(
              _syncOpcode,
              _syncPayload(),
              timeout: const Duration(seconds: 1),
              stage: FlashStage.syncing,
            );
            if (response.value == 0x20120707) {
              _log('ESP32 ROM loader synced at $kBaudRate baud.');
              return;
            }
            throw const FlashException(
              FlashStage.syncing,
              'ESP32 returned an invalid sync response.',
            );
          } on FlashException catch (error) {
            if (error.isDisconnected || _cancelRequested) rethrow;
            lastError = error;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      } on FlashException catch (error) {
        if (error.isDisconnected || _cancelRequested) rethrow;
        lastError = error;
      }
    }
    throw FlashException(
      FlashStage.syncing,
      'Could not connect to ESP32. Hold the BOOT button, press EN/RESET, then try again.',
      details: lastError?.message,
    );
  }

  Uint8List _syncPayload() => Uint8List.fromList([
    0x07,
    0x07,
    0x12,
    0x20,
    ...List<int>.filled(32, 0x55),
  ]);

  Future<void> _resetBoard({required bool alternateTiming}) async {
    final UsbPort? port = _port;
    if (port == null) {
      throw const FlashException(
        FlashStage.enteringBootloader,
        'USB serial port is closed.',
      );
    }
    await port.setDTR(false);
    await port.setRTS(true);
    await Future<void>.delayed(
      Duration(milliseconds: alternateTiming ? 250 : 100),
    );
    await port.setDTR(true);
    await port.setRTS(false);
    await Future<void>.delayed(
      Duration(milliseconds: alternateTiming ? 100 : 50),
    );
    await port.setDTR(false);
  }

  Future<void> _returnToSafeBaudAndSync() async {
    _log('Resetting ESP32 and syncing again at $kBaudRate baud.');
    await _port!.setPortParameters(
      kBaudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _flushInput();
    await _resetAndSync();
  }

  Future<void> _flushInput() async {
    _decoder.reset();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _decoder.reset();
  }

  Future<void> _writeAndVerify(
    Uint8List image, {
    required bool eraseAllFlash,
  }) async {
    _stage(FlashStage.preparingFlash, 'Attaching SPI flash...');
    await _transact(
      _spiAttachOpcode,
      Uint8List(8),
      stage: FlashStage.preparingFlash,
    );
    await _transact(
      _spiSetParamsOpcode,
      EspLoaderProtocol.flashParameters(),
      stage: FlashStage.preparingFlash,
    );

    if (eraseAllFlash) await _eraseEntireFlash();

    final int blockCount = (image.length + kBlockSize - 1) ~/ kBlockSize;
    _stage(FlashStage.preparingFlash, 'Preparing firmware write...');
    await _transact(
      _flashBeginOpcode,
      EspLoaderProtocol.uint32Words([
        image.length,
        blockCount,
        kBlockSize,
        kFlashOffset,
      ]),
      timeout: Duration(seconds: eraseAllFlash ? 120 : 30),
      stage: FlashStage.preparingFlash,
    );

    _progress = 0;
    _stage(FlashStage.writing, 'Writing firmware...');
    for (int block = 0; block < blockCount; block++) {
      _checkActive(FlashStage.writing);
      final int start = block * kBlockSize;
      final int end = math.min(start + kBlockSize, image.length);
      final Uint8List blockData = Uint8List(kBlockSize)
        ..fillRange(0, kBlockSize, 0xFF)
        ..setRange(0, end - start, image, start);
      final Uint8List blockHeader = EspLoaderProtocol.uint32Words([
        kBlockSize,
        block,
        0,
        0,
      ]);
      final Uint8List payload = Uint8List(blockHeader.length + blockData.length)
        ..setRange(0, blockHeader.length, blockHeader)
        ..setRange(
          blockHeader.length,
          blockHeader.length + blockData.length,
          blockData,
        );

      FlashException? lastError;
      for (int attempt = 0; attempt <= 3; attempt++) {
        try {
          await _transact(
            _flashDataOpcode,
            payload,
            checksum: EspLoaderProtocol.checksum(blockData),
            timeout: const Duration(seconds: 5),
            stage: FlashStage.writing,
          );
          lastError = null;
          break;
        } on FlashException catch (error) {
          if (error.isDisconnected || _cancelRequested) rethrow;
          lastError = error;
          if (attempt == 3 || !error.isTimeout) rethrow;
          _log('Retrying block ${block + 1}/$blockCount (${attempt + 1}/3).');
        }
      }
      if (lastError != null) throw lastError;

      _progress = (block + 1) / blockCount;
      if ((block + 1) % math.max(1, blockCount ~/ 100) == 0 ||
          block + 1 == blockCount) {
        _emit(
          FlashEvent(
            stage: FlashStage.writing,
            progress: _progress,
            message: 'Writing ${(_progress * 100).round()}%',
          ),
        );
        if ((block + 1) % math.max(1, blockCount ~/ 10) == 0 ||
            block + 1 == blockCount) {
          _log('Wrote block ${block + 1}/$blockCount.');
        }
      }
    }

    _stage(FlashStage.finishing, 'Verifying written firmware...');
    final Uint8List md5Request = EspLoaderProtocol.uint32Words([
      kFlashOffset,
      image.length,
      0,
      0,
    ]);
    final EspLoaderResponse md5Response = await _transact(
      _spiFlashMd5Opcode,
      md5Request,
      stage: FlashStage.finishing,
    );
    final Uint8List md5Data = md5Response.resultData;
    final String expectedMd5 = md5.convert(image).toString();
    final String actualMd5 = String.fromCharCodes(md5Data).trim().toLowerCase();
    if (actualMd5 != expectedMd5) {
      _log('Expected MD5: $expectedMd5');
      _log('ESP32 MD5: $actualMd5');
      throw const FlashException(
        FlashStage.finishing,
        'Verification failed: flash content does not match',
      );
    }
    _log('Firmware MD5 verified: $actualMd5.');
  }

  Future<void> _eraseEntireFlash() async {
    _stage(
      FlashStage.preparingFlash,
      'Erasing all 4 MiB of flash before writing...',
    );
    final int blockCount = kFlashSize ~/ kBlockSize;
    _log(
      'Flash erase pass: ${EspFlasher.formatSize(kFlashSize)} in $blockCount blocks.',
    );
    await _transact(
      _flashBeginOpcode,
      EspLoaderProtocol.uint32Words([kFlashSize, blockCount, kBlockSize, 0]),
      timeout: const Duration(seconds: 120),
      stage: FlashStage.preparingFlash,
    );

    final Uint8List erasedBlock = Uint8List(kBlockSize)
      ..fillRange(0, kBlockSize, 0xFF);
    final int progressInterval = math.max(1, blockCount ~/ 100);
    for (int block = 0; block < blockCount; block++) {
      _checkActive(FlashStage.preparingFlash);
      final Uint8List header = EspLoaderProtocol.uint32Words([
        kBlockSize,
        block,
        0,
        0,
      ]);
      final Uint8List payload = Uint8List(header.length + erasedBlock.length)
        ..setRange(0, header.length, header)
        ..setRange(
          header.length,
          header.length + erasedBlock.length,
          erasedBlock,
        );
      await _transact(
        _flashDataOpcode,
        payload,
        checksum: EspLoaderProtocol.checksum(erasedBlock),
        timeout: const Duration(seconds: 5),
        stage: FlashStage.preparingFlash,
      );
      if ((block + 1) % progressInterval == 0 || block + 1 == blockCount) {
        _progress = (block + 1) / blockCount;
        _emit(
          FlashEvent(
            stage: FlashStage.preparingFlash,
            progress: _progress,
            message: 'Erasing flash ${(_progress * 100).round()}%',
          ),
        );
      }
      if ((block + 1) % 256 == 0 || block + 1 == blockCount) {
        _log(
          'Erased ${EspFlasher.formatSize((block + 1) * kBlockSize)} of 4.00 MiB.',
        );
      }
    }
  }

  void _checkActive(FlashStage stage) {
    if (_usbDisconnected) {
      throw const FlashException(
        FlashStage.failed,
        'USB disconnected during flashing',
        isDisconnected: true,
      );
    }
    if (_cancelRequested) {
      throw FlashException(stage, 'Flashing was cancelled.');
    }
  }

  void _failPending(FlashException error) {
    final Completer<EspLoaderResponse>? pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  Future<void> _cleanup() async {
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _usbSubscription?.cancel();
    _usbSubscription = null;
    try {
      await _port?.close();
    } catch (error) {
      _log('Could not close USB port cleanly: $error');
    }
    _port = null;
  }

  void _stage(FlashStage stage, String message) {
    _currentStage = stage;
    _log('${_stageName(stage)}: $message');
    _emit(FlashEvent(stage: stage, progress: _progress, message: message));
  }

  void _emit(FlashEvent event) {
    final StreamController<FlashEvent>? events = _events;
    if (events != null && !events.isClosed) events.add(event);
  }

  void _log(String message) {
    final String time = DateTime.now().toIso8601String().substring(11, 19);
    final String entry = '[$time] $message';
    logs.add(entry);
    debugPrint('[EspFlasher] $entry');
  }

  String _stageName(FlashStage stage) {
    switch (stage) {
      case FlashStage.findingDevice:
        return 'Find device';
      case FlashStage.requestingPermission:
        return 'USB permission';
      case FlashStage.connecting:
        return 'Connect';
      case FlashStage.enteringBootloader:
        return 'Bootloader';
      case FlashStage.syncing:
        return 'Sync';
      case FlashStage.preparingFlash:
        return 'Prepare flash';
      case FlashStage.writing:
        return 'Write';
      case FlashStage.finishing:
        return 'Finish';
      case FlashStage.done:
        return 'Done';
      case FlashStage.failed:
        return 'Failed';
    }
  }
}
