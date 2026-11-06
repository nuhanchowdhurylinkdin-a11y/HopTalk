class QrContactData {
  final String userId;
  final String name;
  final String publicKey;
  final String avatar;

  const QrContactData({
    required this.userId,
    required this.name,
    required this.publicKey,
    required this.avatar,
  });

  String get fingerprint => fingerprintOf(publicKey);

  static String fingerprintOf(String key) {
    if (key.length < 8) return key;
    final String hex = key.substring(0, 8);
    return '${hex.substring(0, 4)} ${hex.substring(4, 8)}';
  }
}
