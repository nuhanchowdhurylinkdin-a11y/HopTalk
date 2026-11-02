import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoService {
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  SimpleKeyPair? _keyPair;
  String publicKeyBase64 = '';

  final Map<String, SecretKey> _sessionKeys = {};

  Future<void> init() async {
    final String? savedPrivate = await _storage.read(key: 'x25519_private');
    final String? savedPublic = await _storage.read(key: 'x25519_public');

    if (savedPrivate != null && savedPublic != null) {
      _keyPair = SimpleKeyPairData(
        base64Decode(savedPrivate),
        publicKey: SimplePublicKey(
          base64Decode(savedPublic),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
      publicKeyBase64 = savedPublic;
      return;
    }

    final SimpleKeyPair pair = await _x25519.newKeyPair();
    final List<int> privateBytes = await pair.extractPrivateKeyBytes();
    final SimplePublicKey publicKey = await pair.extractPublicKey();

    publicKeyBase64 = base64Encode(publicKey.bytes);
    await _storage.write(key: 'x25519_private', value: base64Encode(privateBytes));
    await _storage.write(key: 'x25519_public', value: publicKeyBase64);
    _keyPair = pair;
  }

  Future<SecretKey> _sessionKey(String peerPublicKeyBase64) async {
    final cached = _sessionKeys[peerPublicKeyBase64];
    if (cached != null) return cached;

    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: SimplePublicKey(
        base64Decode(peerPublicKeyBase64),
        type: KeyPairType.x25519,
      ),
    );

    final derived = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('hoptalk-hkdf-salt-v1'),
      info: utf8.encode('hoptalk-message-v1'),
    );

    _sessionKeys[peerPublicKeyBase64] = derived;
    return derived;
  }

  Future<String> encrypt(String plainText, String peerPublicKeyBase64) async {
    final key = await _sessionKey(peerPublicKeyBase64);
    final box = await _aes.encrypt(utf8.encode(plainText), secretKey: key);
    return base64Encode(box.concatenation());
  }

  Future<String?> decrypt(String cipherBase64, String peerPublicKeyBase64) async {
    try {
      final key = await _sessionKey(peerPublicKeyBase64);
      final box = SecretBox.fromConcatenation(
        base64Decode(cipherBase64),
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _aes.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (e) {
      return null;
    }
  }
}