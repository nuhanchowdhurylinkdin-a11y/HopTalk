import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/helpers/app_helpers.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/mesh_network/service/esp_flasher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class FlashFirmwareScreen extends StatefulWidget {
  const FlashFirmwareScreen({super.key});

  @override
  State<FlashFirmwareScreen> createState() => _FlashFirmwareScreenState();
}

class _FlashFirmwareScreenState extends State<FlashFirmwareScreen> {
  static const Color _buttonForeground = Color(0xFF202124);

  final EspFlasher _flasher = EspFlasher();
  StreamSubscription<FlashEvent>? _flashSubscription;

  FirmwareImageInfo? _firmwareInfo;
  FlashEvent? _event;
  FlashException? _error;
  String? _loadError;
  String? _deviceName;
  bool _loadingFirmware = true;
  bool _eraseAllFlash = false;
  bool _isFlashing = false;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _loadFirmwareInfo();
  }

  @override
  void dispose() {
    _flashSubscription?.cancel();
    if (_isFlashing) _flasher.cancel();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _loadFirmwareInfo() async {
    try {
      final ByteData data = await rootBundle.load(firmwareAssetPath);
      final Uint8List image = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final FirmwareImageInfo info = FirmwareImageInfo(
        originalSize: image.length,
        flashSize: EspFlasher.trimFirmware(image).length,
      );
      if (!mounted) return;
      setState(() {
        _firmwareInfo = info;
        _loadingFirmware = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Firmware file not found in app.';
        _loadingFirmware = false;
      });
    }
  }

  Future<void> _startFlashing() async {
    if (_isFlashing || _firmwareInfo == null) return;
    setState(() {
      _event = null;
      _error = null;
      _deviceName = null;
      _verified = false;
      _isFlashing = true;
    });

    try {
      await WakelockPlus.enable();
    } catch (_) {}
    if (!mounted) {
      _flasher.cancel();
      return;
    }

    _flashSubscription = _flasher
        .flash(eraseAllFlash: _eraseAllFlash)
        .listen(
          _onFlashEvent,
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isFlashing = false;
              _error = FlashException(FlashStage.failed, error.toString());
            });
            unawaited(WakelockPlus.disable());
          },
          onDone: () {
            if (!mounted) return;
            if (_isFlashing) {
              setState(() {
                _isFlashing = false;
                _error ??= const FlashException(
                  FlashStage.failed,
                  'Flashing stopped before it finished.',
                );
              });
            }
            unawaited(WakelockPlus.disable());
          },
        );
  }

  void _onFlashEvent(FlashEvent event) {
    if (!mounted) return;
    setState(() {
      _event = event;
      _deviceName = _flasher.deviceName ?? _deviceName;
      if (event.stage == FlashStage.done) {
        _isFlashing = false;
        _verified = true;
      } else if (event.stage == FlashStage.failed) {
        _isFlashing = false;
        _error =
            event.error ?? FlashException(FlashStage.failed, event.message);
      }
    });
    if (event.stage == FlashStage.done || event.stage == FlashStage.failed) {
      unawaited(WakelockPlus.disable());
    }
  }

  Future<void> _confirmLeaveWhileFlashing() async {
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop firmware flashing?'),
        content: const Text(
          'Leaving now may leave the ESP32 firmware incomplete. Stop flashing and leave this screen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: _buttonForeground),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(foregroundColor: _buttonForeground),
            child: const Text('Stop and leave'),
          ),
        ],
      ),
    );
    if (leave != true) return;
    await _flashSubscription?.cancel();
    _flasher.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _flasher.logs.join('\n')));
    if (!mounted) return;
    AppHelpers.showSuccessSnackbar(
      title: 'Log copied',
      message: 'Flashing log copied to clipboard.',
    );
  }

  void _tryAgain() {
    if (_isFlashing) return;
    _startFlashing();
  }

  Duration get _estimatedDuration {
    final int size = _firmwareInfo?.flashSize ?? 0;
    return EspFlasher.estimateDuration(
      imageSize: size,
      baudRate: kFastBaudRate,
      eraseAllFlash: _eraseAllFlash,
    );
  }

  String get _estimatedText {
    final int minutes = (_estimatedDuration.inSeconds / 60)
        .ceil()
        .clamp(1, 999)
        .toInt();
    return 'Estimated time: about $minutes min at $kFastBaudRate baud.';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return PopScope<Object?>(
      canPop: !_isFlashing,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _isFlashing) unawaited(_confirmLeaveWhileFlashing());
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Flash Firmware'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ScreenUtils screen = ScreenUtils.fromConstraints(
                constraints,
              );
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  screen.horizontalPadding,
                  screen.isSmallPhone ? 8 : 16,
                  screen.horizontalPadding,
                  screen.isSmallPhone ? 16 : 24,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildInstructionsCard(context),
                          SizedBox(height: screen.sectionGap * 0.7),
                          if (_isFlashing) _buildProgressCard(context),
                          if (_error != null) _buildErrorCard(context),
                          if (_verified) _buildSuccessCard(context),
                          if (!_isFlashing && !_verified)
                            _buildControls(context),
                          if (_loadError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _loadError!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionsCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final FirmwareImageInfo? info = _firmwareInfo;

    return Card(
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect an ESP32 board using a USB OTG adapter.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'If the board does not enter download mode, hold BOOT and press EN/RESET.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _InfoLine(
              label: 'USB device',
              value:
                  _deviceName ??
                  (_isFlashing ? 'Searching...' : 'Not connected'),
            ),
            const SizedBox(height: 8),
            _InfoLine(
              label: 'Firmware file',
              value: info == null
                  ? (_loadingFirmware ? 'Loading...' : 'Unavailable')
                  : EspFlasher.formatSize(info.originalSize),
            ),
            const SizedBox(height: 8),
            _InfoLine(
              label: 'Will write',
              value: info == null ? '—' : EspFlasher.formatSize(info.flashSize),
            ),
            const SizedBox(height: 8),
            Text(
              _estimatedText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool canStart =
        !_isFlashing && !_loadingFirmware && _firmwareInfo != null;

    return Card(
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _eraseAllFlash,
              onChanged: _isFlashing
                  ? null
                  : (bool value) => setState(() => _eraseAllFlash = value),
              title: const Text('Erase all flash before writing'),
              subtitle: const Text(
                'Clears all 4 MiB, including stored settings and data.',
              ),
            ),
            if (_error == null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canStart ? _startFlashing : null,
                  icon: _loadingFirmware
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.usb),
                  label: Text(
                    _loadingFirmware ? 'Loading firmware...' : 'Start Flashing',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: _buttonForeground,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final double progress = _event?.progress.clamp(0, 1).toDouble() ?? 0;

    return Card(
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Firmware update', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                color: colors.primary,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _event?.message ?? 'Starting...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text('${(progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 16),
            for (int index = 0; index < _stepNames.length; index++)
              _buildStep(context, index),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int activeIndex = _activeStep(
      _event?.stage ?? FlashStage.findingDevice,
    );
    final bool failed = _error != null && activeIndex == index;
    final bool complete = _verified || (index < activeIndex && !failed);
    final bool running = _isFlashing && index == activeIndex && !failed;
    final IconData icon = failed
        ? Icons.error
        : complete
        ? Icons.check_circle
        : running
        ? Icons.radio_button_checked
        : Icons.radio_button_unchecked;
    final Color color = failed
        ? colors.error
        : complete
        ? colors.secondary
        : running
        ? colors.primary
        : colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Text(
            _stepNames[index],
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: running ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final FlashException error = _error!;

    return Card(
      color: colors.errorContainer,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed during ${_stageLabel(error.stage)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              error.message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
            if (error.code != null) ...[
              const SizedBox(height: 6),
              Text(
                'Error code: 0x${error.code!.toRadixString(16).padLeft(2, '0')}',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _suggestedFix(error),
              style: TextStyle(color: colors.onErrorContainer),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Details / Log'),
              children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _flasher.logs.isEmpty
                          ? (error.details ?? error.message)
                          : _flasher.logs.join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _copyLog,
                    style: TextButton.styleFrom(
                      foregroundColor: _buttonForeground,
                    ),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy log'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _tryAgain,
                style: FilledButton.styleFrom(
                  foregroundColor: _buttonForeground,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Card(
      color: colors.secondaryContainer,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.verified, color: colors.onSecondaryContainer, size: 36),
            const SizedBox(height: 8),
            Text(
              'Verified',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Firmware flashed successfully. The device is restarting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Get.back<void>(),
                style: FilledButton.styleFrom(
                  foregroundColor: _buttonForeground,
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _activeStep(FlashStage stage) {
    switch (stage) {
      case FlashStage.findingDevice:
      case FlashStage.requestingPermission:
        return 0;
      case FlashStage.connecting:
      case FlashStage.enteringBootloader:
        return 1;
      case FlashStage.syncing:
        return 2;
      case FlashStage.preparingFlash:
      case FlashStage.writing:
        return 3;
      case FlashStage.finishing:
      case FlashStage.done:
      case FlashStage.failed:
        return 4;
    }
  }

  String _stageLabel(FlashStage stage) {
    switch (stage) {
      case FlashStage.findingDevice:
        return 'finding device';
      case FlashStage.requestingPermission:
        return 'USB permission';
      case FlashStage.connecting:
        return 'connecting';
      case FlashStage.enteringBootloader:
        return 'entering bootloader';
      case FlashStage.syncing:
        return 'syncing';
      case FlashStage.preparingFlash:
        return 'preparing flash';
      case FlashStage.writing:
        return 'writing';
      case FlashStage.finishing:
        return 'verifying';
      case FlashStage.done:
        return 'finishing';
      case FlashStage.failed:
        return 'flashing';
    }
  }

  String _suggestedFix(FlashException error) {
    if (error.isDisconnected) {
      return 'Reconnect the board with a data-capable OTG cable, then try again.';
    }
    switch (error.stage) {
      case FlashStage.findingDevice:
        return 'Check the OTG adapter and use a cable that supports data, not charging only.';
      case FlashStage.requestingPermission:
      case FlashStage.connecting:
        return 'Approve the USB permission. If the board draws too much power, try a powered OTG hub.';
      case FlashStage.enteringBootloader:
      case FlashStage.syncing:
        return 'Hold BOOT, press EN/RESET, then release BOOT when sync starts.';
      case FlashStage.preparingFlash:
      case FlashStage.writing:
      case FlashStage.finishing:
        return 'Keep the board connected and powered. Try again with a stable OTG adapter.';
      case FlashStage.done:
      case FlashStage.failed:
        return 'Check the USB cable and board power, then try again.';
    }
  }
}

const List<String> _stepNames = [
  'Find device',
  'Connect',
  'Sync',
  'Write',
  'Finish',
];

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
        ),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    );
  }
}
