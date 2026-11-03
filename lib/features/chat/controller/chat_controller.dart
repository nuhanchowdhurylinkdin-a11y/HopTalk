import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hop_talk/features/chat/models/chat_message.dart';
import 'package:hop_talk/features/chat/service/chat_storage_service.dart';
import 'package:hop_talk/features/mesh_network/controller/mesh_network_controller.dart';

class ChatController extends GetxController {
  ChatController({required this.peerId});

  final String peerId;
  final int pageSize = 30;
  static const int _receiptChunk = 100;

  final MeshNetworkController _mesh = Get.find<MeshNetworkController>();
  final ChatStorageService _storage = Get.find<ChatStorageService>();

  final RxList<ChatMessage> messages = <ChatMessage>[].obs; // newest first
  final RxBool isInitialLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = false.obs;
  final ScrollController scrollController = ScrollController();

  final List<ChatMessage> _bufferedLive = [];
  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<SeenUpdate>? _seenSubscription;
  int? _oldestKey;
  bool _isSending = false;
  bool _isAcknowledging = false;
  bool _ackQueued = false;

  bool isMine(ChatMessage message) => message.senderId == _mesh.currentUserId;

  bool _belongsToThisChat(ChatMessage message) {
    return message.senderId == peerId || message.targetId == peerId;
  }

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    _messageSubscription = _mesh.messageStream.listen(_onLiveMessage);
    _seenSubscription = _mesh.seenStream.listen(_onSeenUpdate);
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    try {
      final ChatPage page = await _storage.loadPage(peerId, limit: pageSize);
      messages.assignAll(page.messages);
      _oldestKey = page.oldestKey;
      hasMore.value = page.hasMore;
    } catch (e) {
      debugPrint('Could not load chat: $e');
    } finally {
      isInitialLoading.value = false;
    }

    for (final message in _bufferedLive) {
      _insertLive(message);
    }
    _bufferedLive.clear();

    _acknowledgeIncoming();
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || _oldestKey == null) return;

    isLoadingMore.value = true;
    try {
      final ChatPage page = await _storage.loadPage(
        peerId,
        beforeKey: _oldestKey,
        limit: pageSize,
      );
      messages.addAll(page.messages);
      _oldestKey = page.oldestKey ?? _oldestKey;
      hasMore.value = page.hasMore;
    } catch (e) {
      debugPrint('Could not load older messages: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      loadMore();
    }
  }

  void _onLiveMessage(ChatMessage message) {
    if (!_belongsToThisChat(message)) return;

    if (isInitialLoading.value) {
      _bufferedLive.add(message);
      return;
    }

    _insertLive(message);

    if (!isMine(message)) {
      _acknowledgeIncoming();
    }
  }

  void _insertLive(ChatMessage message) {
    final bool exists = messages.any((m) => m.messageId == message.messageId);
    if (exists) return;
    messages.insert(0, message);
  }

  void _onSeenUpdate(SeenUpdate update) {
    if (update.peerId != peerId) return;

    final Set<String> ids = update.messageIds.toSet();
    for (int i = 0; i < messages.length; i++) {
      final ChatMessage message = messages[i];
      if (!message.seen && isMine(message) && ids.contains(message.messageId)) {
        messages[i] = message.copyWith(seen: true);
      }
    }
  }

  Future<void> _acknowledgeIncoming() async {
    if (_isAcknowledging) {
      _ackQueued = true;
      return;
    }

    _isAcknowledging = true;
    try {
      do {
        _ackQueued = false;

        await _storage.markRead(peerId);

        final List<String> newestFirst = await _storage.unseenIncomingIds(
          peerId,
        );

        if (newestFirst.isNotEmpty) {
          final List<String> ids = newestFirst.reversed.toList();

          for (int i = 0; i < ids.length; i += _receiptChunk) {
            final List<String> chunk = ids.sublist(
              i,
              math.min(i + _receiptChunk, ids.length),
            );

            final bool sent = await _mesh.sendSeenReceipt(peerId, chunk);
            if (!sent) break;

            await _storage.markIncomingSeen(peerId, chunk.toSet());
          }
        }
      } while (_ackQueued);
    } catch (e) {
      debugPrint('Could not send seen receipt: $e');
    } finally {
      _isAcknowledging = false;
    }
  }

  Future<bool> send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return false;

    _isSending = true;
    try {
      return await _mesh.broadcastMessage(peerId, trimmed, false);
    } finally {
      _isSending = false;
    }
  }

  @override
  void onClose() {
    _messageSubscription?.cancel();
    _seenSubscription?.cancel();
    scrollController.dispose();
    super.onClose();
  }
}