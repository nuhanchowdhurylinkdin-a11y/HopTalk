import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:hop_talk/features/chat/models/chat_message.dart';

class ChatPage {
  const ChatPage({
    required this.messages,
    required this.oldestKey,
    required this.hasMore,
  });

  final List<ChatMessage> messages; // newest first
  final int? oldestKey;
  final bool hasMore;
}

class SeenUpdate {
  const SeenUpdate({required this.peerId, required this.messageIds});

  final String peerId;
  final List<String> messageIds;
}

class ChatStorageService extends GetxService {
  static const String _conversationsBoxName = 'conversationsBox';
  static const String _secureKeyName = 'hive_chat_key';
  static const int maxMessagesPerConversation = 2000;
  static const int _trimBatch = 100;
  static const int _previewLength = 80;
  static const int _scanLimit = 600;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Map<String, Future<LazyBox<ChatMessage>>> _openBoxes = {};

  late final HiveAesCipher _cipher;
  late Box _conversations;

  Future<ChatStorageService> init() async {
    _cipher = HiveAesCipher(await _loadOrCreateKey());

    try {
      _conversations = await Hive.openBox(
        _conversationsBoxName,
        encryptionCipher: _cipher,
      );
    } catch (e) {
      await Hive.deleteBoxFromDisk(_conversationsBoxName);
      _conversations = await Hive.openBox(
        _conversationsBoxName,
        encryptionCipher: _cipher,
      );
    }

    return this;
  }

  Future<List<int>> _loadOrCreateKey() async {
    try {
      final String? saved = await _secureStorage.read(key: _secureKeyName);
      if (saved != null) {
        final List<int> key = base64Url.decode(saved);
        if (key.length == 32) return key;
      }
    } catch (e) {
      // Key could not be read. A new key is created below.
    }

    final List<int> key = Hive.generateSecureKey();
    await _secureStorage.write(
      key: _secureKeyName,
      value: base64Url.encode(key),
    );
    return key;
  }

  String _boxName(String peerId) {
    final String safe = peerId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return 'chat_$safe';
  }

  Future<LazyBox<ChatMessage>> _boxFor(String peerId) async {
    final String name = _boxName(peerId);
    final Future<LazyBox<ChatMessage>> future = _openBoxes.putIfAbsent(
      name,
          () => _openConversationBox(name),
    );

    try {
      return await future;
    } catch (e) {
      _openBoxes.remove(name);
      rethrow;
    }
  }

  Future<LazyBox<ChatMessage>> _openConversationBox(String name) async {
    try {
      return await Hive.openLazyBox<ChatMessage>(
        name,
        encryptionCipher: _cipher,
      );
    } catch (e) {
      await Hive.deleteBoxFromDisk(name);
      return Hive.openLazyBox<ChatMessage>(name, encryptionCipher: _cipher);
    }
  }

  Map<String, dynamic> _meta(String peerId) {
    final dynamic existing = _conversations.get(peerId);
    if (existing is Map) return Map<String, dynamic>.from(existing);

    return {
      'peerId': peerId,
      'peerName': '',
      'avatar': '',
      'image': '',
      'lastBody': '',
      'lastTimestamp': 0,
      'lastIsMine': false,
      'lastMessageId': '',
      'lastMessageSeen': false,
      'unreadCount': 0,
    };
  }

  Future<void> saveContact({
    required String peerId,
    required String name,
    required String avatar,
    required String image,
  }) async {
    final bool exists = _conversations.containsKey(peerId);
    final Map<String, dynamic> meta = _meta(peerId);

    if (exists &&
        meta['peerName'] == name &&
        meta['avatar'] == avatar &&
        meta['image'] == image) {
      return;
    }

    meta['peerName'] = name;
    meta['avatar'] = avatar;
    meta['image'] = image;
    await _conversations.put(peerId, meta);
  }

  Future<void> saveMessage({
    required String peerId,
    required String peerName,
    required ChatMessage message,
    required bool isIncoming,
  }) async {
    final LazyBox<ChatMessage> box = await _boxFor(peerId);
    await box.add(message);
    await _trimIfNeeded(box);

    final Map<String, dynamic> meta = _meta(peerId);
    if (((meta['peerName'] as String?) ?? '').isEmpty) {
      meta['peerName'] = peerName;
    }
    meta['lastBody'] = String.fromCharCodes(
      message.body.runes.take(_previewLength),
    );
    meta['lastTimestamp'] = message.timestamp;
    meta['lastIsMine'] = !isIncoming;
    meta['lastMessageId'] = message.messageId;
    meta['lastMessageSeen'] = message.seen;
    meta['unreadCount'] =
        ((meta['unreadCount'] as int?) ?? 0) + (isIncoming ? 1 : 0);

    await _conversations.put(peerId, meta);
  }

  Future<void> _trimIfNeeded(LazyBox<ChatMessage> box) async {
    if (box.length <= maxMessagesPerConversation + _trimBatch) return;

    final int excess = box.length - maxMessagesPerConversation;
    final List<int> keys = box.keys.cast<int>().toList()..sort();
    await box.deleteAll(keys.take(excess));
  }

  Future<ChatPage> loadPage(
      String peerId, {
        int? beforeKey,
        int limit = 30,
      }) async {
    final LazyBox<ChatMessage> box = await _boxFor(peerId);

    final List<int> keys = box.keys.cast<int>().toList()..sort();
    final List<int> candidates = beforeKey == null
        ? keys
        : keys.where((key) => key < beforeKey).toList();

    if (candidates.isEmpty) {
      return const ChatPage(messages: [], oldestKey: null, hasMore: false);
    }

    final int start = candidates.length > limit ? candidates.length - limit : 0;
    final List<int> pageKeys = candidates.sublist(start);

    final List<ChatMessage> messages = [];
    for (final key in pageKeys.reversed) {
      final ChatMessage? message = await box.get(key);
      if (message != null) messages.add(message);
    }

    return ChatPage(
      messages: messages,
      oldestKey: pageKeys.first,
      hasMore: start > 0,
    );
  }

  Future<void> markRead(String peerId) async {
    final dynamic existing = _conversations.get(peerId);
    if (existing is! Map) return;
    if (((existing['unreadCount'] as int?) ?? 0) == 0) return;

    final Map<String, dynamic> updated = Map<String, dynamic>.from(existing);
    updated['unreadCount'] = 0;
    await _conversations.put(peerId, updated);
  }

  // Incoming messages that have no "seen" receipt yet, newest first.
  Future<List<String>> unseenIncomingIds(String peerId) async {
    final LazyBox<ChatMessage> box = await _boxFor(peerId);
    final List<int> keys = box.keys.cast<int>().toList()..sort();

    final List<String> ids = [];
    int scanned = 0;

    for (final key in keys.reversed) {
      if (scanned >= _scanLimit) break;
      scanned++;

      final ChatMessage? message = await box.get(key);
      if (message == null || message.senderId != peerId) continue;
      if (message.seen) break;
      ids.add(message.messageId);
    }

    return ids;
  }

  Future<void> markIncomingSeen(String peerId, Set<String> ids) async {
    final LazyBox<ChatMessage> box = await _boxFor(peerId);
    final List<int> keys = box.keys.cast<int>().toList()..sort();

    final Set<String> remaining = Set<String>.from(ids);
    int scanned = 0;

    for (final key in keys.reversed) {
      if (remaining.isEmpty || scanned >= _scanLimit) break;
      scanned++;

      final ChatMessage? message = await box.get(key);
      if (message == null || message.senderId != peerId) continue;
      if (!remaining.remove(message.messageId)) continue;
      if (message.seen) continue;

      await box.put(key, message.copyWith(seen: true));
    }
  }

  // Called when the other person confirms they saw my messages.
  Future<List<String>> markOutgoingSeen(String peerId, Set<String> ids) async {
    final LazyBox<ChatMessage> box = await _boxFor(peerId);
    final List<int> keys = box.keys.cast<int>().toList()..sort();

    final Set<String> remaining = Set<String>.from(ids);
    final List<String> updated = [];
    int scanned = 0;

    for (final key in keys.reversed) {
      if (remaining.isEmpty || scanned >= _scanLimit) break;
      scanned++;

      final ChatMessage? message = await box.get(key);
      if (message == null || message.senderId == peerId) continue;
      if (!remaining.remove(message.messageId)) continue;
      if (message.seen) continue;

      await box.put(key, message.copyWith(seen: true));
      updated.add(message.messageId);
    }

    if (updated.isNotEmpty) {
      final Map<String, dynamic> meta = _meta(peerId);
      if (updated.contains(meta['lastMessageId'])) {
        meta['lastMessageSeen'] = true;
        await _conversations.put(peerId, meta);
      }
    }

    return updated;
  }

  List<Map<String, dynamic>> getConversations() {
    final List<Map<String, dynamic>> list = _conversations.values
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    list.sort((a, b) {
      final int ta = (a['lastTimestamp'] as int?) ?? 0;
      final int tb = (b['lastTimestamp'] as int?) ?? 0;
      if (ta != tb) return tb.compareTo(ta);
      return ((a['peerName'] as String?) ?? '').compareTo(
        (b['peerName'] as String?) ?? '',
      );
    });

    return list;
  }

  Stream<BoxEvent> watchConversations() => _conversations.watch();

  Future<void> deleteConversation(String peerId) async {
    final String name = _boxName(peerId);
    final Future<LazyBox<ChatMessage>>? opening = _openBoxes.remove(name);

    if (opening != null) {
      try {
        final LazyBox<ChatMessage> box = await opening;
        await box.close();
      } catch (e) {
        // Box was not open, nothing to close.
      }
    }

    await Hive.deleteBoxFromDisk(name);
    await _conversations.delete(peerId);
  }
}