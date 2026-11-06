import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/core/utils/constants/colors.dart';
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
      Get.snackbar(
        "Invalid QR",
        "This QR code is not a valid HopTalk contact",
        snackPosition: SnackPosition.BOTTOM,
      );
      await Future.delayed(const Duration(seconds: 2));
      _busy = false;
      return;
    }

    final String? error = mesh.validateQrContact(data);
    if (error != null) {
      Get.snackbar(
        "Cannot Add Contact",
        error,
        snackPosition: SnackPosition.BOTTOM,
      );
      await Future.delayed(const Duration(seconds: 2));
      _busy = false;
      return;
    }

    await _showConfirmSheet(data);
    _busy = false;
  }

  Future<void> _showConfirmSheet(QrContactData data) async {
    final result = await Get.bottomSheet<bool>(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
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
            const SizedBox(height: 16),
            Text(
              data.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Key fingerprint: ${data.fingerprint}",
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text("Cancel"),
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
                    child: const Text("Add contact"),
                  ),
                ),
              ],
            ),
          ],
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
          title: const Text("Key Changed"),
          content: Text(
            "The encryption key for ${data.name} has changed. This can happen if they reinstalled the app. "
            "Do you want to replace the old key with this new one? Old messages will not be readable.",
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text("Replace Key"),
            ),
          ],
        ),
      );

      if (replace == true) {
        final String? retryError = await mesh.saveQrContact(data, replaceKey: true);
        if (retryError != null && retryError != MeshNetworkController.keyChangedError) {
          Get.snackbar("Error", retryError, snackPosition: SnackPosition.BOTTOM);
          return;
        }
      } else {
        return;
      }
    } else if (saveError != null) {
      Get.snackbar("Error", saveError, snackPosition: SnackPosition.BOTTOM);
      return;
    }

    _switchToMyQr();
    Get.snackbar(
      "Contact Added",
      "${data.name} added. Now ask them to scan this QR too.",
      backgroundColor: Colors.green,
      colorText: Colors.white,
      snackPosition: SnackPosition.TOP,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text("My QR")),
                ButtonSegment(value: 1, label: Text("Scan")),
              ],
              selected: {_selectedIndex},
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
              onPressed: () {
                _scannerController?.toggleTorch();
                setState(() => _torchEnabled = !_torchEnabled);
              },
            ),
        ],
      ),
      body: _selectedIndex == 0 ? _buildMyQrView(mesh) : _buildScanView(),
    );
  }

  Widget _buildMyQrView(MeshNetworkController mesh) {
    return FutureBuilder<String>(
      future: mesh.buildMyQrPayload(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: snapshot.data!,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  mesh.displayNameOf(mesh.currentUserId),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Key fingerprint: ${mesh.myFingerprint}",
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Both people must scan each other's QR for LoRa messages to be readable.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black87),
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

    return MobileScanner(
      controller: _scannerController!,
      onDetect: _onDetect,
    );
  }
}
