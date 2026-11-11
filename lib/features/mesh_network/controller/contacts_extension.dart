part of 'mesh_network_controller.dart';

extension MeshContacts on MeshNetworkController {
  Future<String> buildMyQrPayload() async {
    if (_crypto.publicKeyBase64.isEmpty) {
      await _crypto.init();
    }
    return jsonEncode({
      'v': 1,
      'u': _currentUserId,
      'n': _limitRunes(_userName, _maxProfileNameLength),
      'k': _crypto.publicKeyBase64,
      'a': _sanitizeAvatar(_avatar),
    });
  }

  QrContactData? parseContactQr(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final int? version = decoded['v'] as int?;
      if (version != 1) return null;

      final String? userId = decoded['u'] as String?;
      if (userId == null || userId.isEmpty || userId.length > 64) return null;

      final dynamic nameRaw = decoded['n'];
      if (nameRaw is! String) return null;
      final String name = _limitRunes(nameRaw, _maxProfileNameLength);

      final String publicKey = _sanitizePublicKey(decoded['k']);
      if (publicKey.isEmpty) return null;

      final String avatar = _sanitizeAvatar(decoded['a']);

      return QrContactData(
        userId: userId,
        name: name,
        publicKey: publicKey,
        avatar: avatar,
      );
    } catch (e) {
      return null;
    }
  }

  String? validateQrContact(QrContactData data) {
    if (_isSelf(data.userId)) {
      return "You cannot add yourself as a contact";
    }
    if (_isBlockedUser(data.userId)) {
      return "This user is blocked";
    }
    return null;
  }

  Future<String?> saveQrContact(
    QrContactData data, {
    bool replaceKey = false,
  }) async {
    final String pinnedKey = _chatStorage.pinnedKeyOf(data.userId);
    if (pinnedKey.isNotEmpty && pinnedKey != data.publicKey && !replaceKey) {
      return MeshNetworkController.keyChangedError;
    }

    final Map<String, dynamic>? existing = knownProfiles[data.userId];
    if (existing != null) {
      final String existingKey = (existing['publicKey'] as String?) ?? '';
      final bool isUnpinned = pinnedKey.isEmpty;
      if (isUnpinned &&
          existingKey.isNotEmpty &&
          existingKey != data.publicKey) {
        knownProfiles[data.userId] = {
          'name': data.name,
          'avatar': data.avatar,
          'image': '',
          'publicKey': data.publicKey,
          'version': 0,
          'local': true,
        };
      }
    } else {
      knownProfiles[data.userId] = {
        'name': data.name,
        'avatar': data.avatar,
        'image': '',
        'publicKey': data.publicKey,
        'version': 0,
        'local': true,
      };
    }

    knownUsers[data.userId] = data.name;

    try {
      await _chatStorage.saveContact(
        peerId: data.userId,
        name: data.name,
        avatar: data.avatar,
        image: '',
        publicKey: data.publicKey,
        qr: true,
      );
    } catch (e) {
      _log("Could not save QR contact: $e");
      return "Failed to save contact: $e";
    }

    await _flushPendingFor(data.userId);
    update();
    return null;
  }

  void forgetContact(String peerId) {
    knownProfiles.remove(peerId);
    knownUsers.remove(peerId);
    update();
  }

  Future<void> _loadSavedContacts() async {
    final List<Map<String, dynamic>> qrContacts = _chatStorage.getQrContacts();
    for (final conv in qrContacts) {
      final String peerId = conv['peerId'] as String;
      final String publicKey = (conv['publicKey'] as String?) ?? '';
      if (publicKey.isEmpty) continue;

      final String name = (conv['peerName'] as String?) ?? '';
      final String avatar = (conv['avatar'] as String?) ?? '';

      knownProfiles.putIfAbsent(
        peerId,
        () => {
          'name': name,
          'avatar': avatar,
          'image': '',
          'publicKey': publicKey,
          'version': 0,
          'local': true,
        },
      );
      knownUsers[peerId] = name;
    }
  }

}
