import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
import 'package:hop_talk/core/utils/helpers/app_helpers.dart';
import 'package:hop_talk/core/utils/helpers/screen_utils.dart';
import 'package:hop_talk/features/home/views/widgets/build_profile_image.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';
import 'package:hop_talk/features/mesh_network/models/qr_contact.dart';
import 'package:hop_talk/features/setup/models/user_profile.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrScreen extends StatefulWidget {
  const QrScreen({super.key, this.startOnScan = false});

  final bool startOnScan;

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  int _selectedIndex = 0;
  MobileScannerController? _scannerController;
  bool _busy = false;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    if (widget.startOnScan) {
      _selectedIndex = 1;
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _switchToMyQr() {
    setState(() {
      _selectedIndex = 0;
      _scannerController?.dispose();
      _scannerController = null;
    });
  }

  void _onSegmentChanged(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        _scannerController?.dispose();
        _scannerController = null;
      }
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _busy = true;

    final MeshNetworkController mesh = Get.find<MeshNetworkController>();
    final QrContactData? data = mesh.parseContactQr(rawValue);

    if (data == null) {
      AppHelpers.showErrorSnackbar(
        title: 'Invalid QR',
        message: 'This QR code is not a valid HopTalk contact',
      );
      await Future.delayed(const Duration(seconds: 2));
      _busy = false;
      return;
    }

    final String? error = mesh.validateQrContact(data);
    if (error != null) {
      AppHelpers.showErrorSnackbar(title: 'Cannot Add Contact', message: error);
      await Future.delayed(const Duration(seconds: 2));
      _busy = false;
      return;
    }

    await _showConfirmSheet(data, ScreenUtils.of(context));
    _busy = false;
  }

  Future<void> _showConfirmSheet(QrContactData data, ScreenUtils screen) async {
    final result = await Get.bottomSheet<bool>(
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: EdgeInsets.all(screen.isSmallPhone ? 18 : 24),
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: screen.isSmallPhone ? 34 : 40,
                  backgroundColor: Colors.transparent,
                  child: ClipOval(
                    child: BuildProfileImage(
                      profile: UserProfile(
                        userId: data.userId,
                        name: data.name,
                        avatar: data.avatar,
                        imagePath: '',
                        compressedImage: '',
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screen.isSmallPhone ? 12 : 16),
                Text(
                  data.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screen.isSmallPhone ? 18 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Key fingerprint: ${data.fingerprint}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screen.isSmallPhone ? 12 : 14,
                    color: const Color(0xFF454836),
                  ),
                ),
                SizedBox(height: screen.isSmallPhone ? 18 : 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Get.back(result: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: const BorderSide(color: AppColors.secondary),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Get.back(result: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.neutral,
                        ),
                        child: const Text('Add contact'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      isDismissible: true,
      enableDrag: true,
    );

    if (result != true) return;

    final MeshNetworkController mesh = Get.find<MeshNetworkController>();
    final String? saveError = await mesh.saveQrContact(data);

    if (saveError == MeshNetworkController.keyChangedError) {
      final bool? replace = await Get.dialog<bool>(
        AlertDialog(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: const Text("Key Changed"),
          content: Text(
            "The encryption key for ${data.name} has changed. This can happen if they reinstalled the app. "
            "Do you want to replace the old key with this new one? Old messages will not be readable.",
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
              child: const Text("Replace Key"),
            ),
          ],
        ),
      );

      if (replace == true) {
        final String? retryError = await mesh.saveQrContact(
          data,
          replaceKey: true,
        );
        if (retryError != null &&
            retryError != MeshNetworkController.keyChangedError) {
          AppHelpers.showErrorSnackbar(title: 'Error', message: retryError);
          return;
        }
      } else {
        return;
      }
    } else if (saveError != null) {
      AppHelpers.showErrorSnackbar(title: 'Error', message: saveError);
      return;
    }

    _switchToMyQr();
    AppHelpers.showSuccessSnackbar(
      title: 'Contact Added',
      message: '${data.name} added. Now ask them to scan this QR too.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final MeshNetworkController mesh = Get.find<MeshNetworkController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("QR Contact Exchange"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenUtils.of(context).horizontalPadding,
              vertical: 8,
            ),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text("My QR")),
                ButtonSegment(value: 1, label: Text("Scan")),
              ],
              selected: {_selectedIndex},
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.neutral
                      : AppColors.secondary,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.primary
                      : AppColors.primarySurface,
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: AppColors.secondary),
                ),
                overlayColor: WidgetStatePropertyAll(
                  AppColors.primary.withValues(alpha: 0.16),
                ),
              ),
              onSelectionChanged: (Set<int> selection) {
                _onSegmentChanged(selection.first);
              },
            ),
          ),
        ),
        actions: [
          if (_selectedIndex == 1)
            IconButton(
              icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
              color: AppColors.secondary,
              tooltip: _torchEnabled ? 'Turn torch off' : 'Turn torch on',
              onPressed: () {
                _scannerController?.toggleTorch();
                setState(() => _torchEnabled = !_torchEnabled);
              },
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screen = ScreenUtils.fromConstraints(constraints);
          return _selectedIndex == 0
              ? _buildMyQrView(mesh, screen)
              : _buildScanView();
        },
      ),
    );
  }

  Widget _buildMyQrView(MeshNetworkController mesh, ScreenUtils screen) {
    return FutureBuilder<String>(
      future: mesh.buildMyQrPayload(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.secondary),
          );
        }

        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(screen.isSmallPhone ? 16 : 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(screen.isSmallPhone ? 12 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: snapshot.data!,
                    version: QrVersions.auto,
                    size: screen.isSmallPhone
                        ? 200
                        : screen.isLargePhone
                        ? 280
                        : 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                SizedBox(height: screen.sectionGap),
                Text(
                  mesh.displayNameOf(mesh.currentUserId),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screen.isSmallPhone ? 18 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Key fingerprint: ${mesh.myFingerprint}",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screen.isSmallPhone ? 12 : 14,
                    color: const Color(0xFF454836),
                  ),
                ),
                SizedBox(height: screen.sectionGap),
                Container(
                  padding: EdgeInsets.all(screen.isSmallPhone ? 12 : 16),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Both people must scan each other's QR for LoRa messages to be readable.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screen.isSmallPhone ? 13 : 14,
                      color: AppColors.neutral,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanView() {
    _scannerController ??= MobileScannerController();

    return MobileScanner(controller: _scannerController!, onDetect: _onDetect);
  }
}
