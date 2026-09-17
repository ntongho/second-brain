import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:second_brain/core/network/connectivity.dart';
import 'package:second_brain/core/storage/local_cache.dart';
import 'package:second_brain/features/chat/data/chat_repository.dart';
import 'package:second_brain/features/chat/domain/chat_message.dart';
import 'package:uuid/uuid.dart';

final devModeProvider = StateProvider<bool>((ref) => false);

class ChatState {
  const ChatState({
    this.chatId,
    this.messages = const [],
    this.streaming = false,
    this.degraded = false,
    this.offline = false,
    this.pinnedToBottom = true,
  });

  final String? chatId;
  final List<ChatMessage> messages;
  final bool streaming;
  final bool degraded;
  final bool offline;
  final bool pinnedToBottom;

  ChatState copyWith({
    String? chatId,
    List<ChatMessage>? messages,
    bool? streaming,
    bool? degraded,
    bool? offline,
    bool? pinnedToBottom,
    bool clearChatId = false,
  }) {
    return ChatState(
      chatId: clearChatId ? null : (chatId ?? this.chatId),
      messages: messages ?? this.messages,
      streaming: streaming ?? this.streaming,
      degraded: degraded ?? this.degraded,
      offline: offline ?? this.offline,
      pinnedToBottom: pinnedToBottom ?? this.pinnedToBottom,
    );
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

String? apiChatId(String? id) {
  if (id == null || id.isEmpty || id.startsWith('local_')) return null;
  return id;
}

class ChatNotifier extends Notifier<ChatState> {
  CancelToken? _cancel;
  static const _uuid = Uuid();
  var _fresh = false;

  @override
  ChatState build() {
    ref.listen<bool>(connectivityProvider, (prev, online) {
      if (state.offline == !online) return;
      state = state.copyWith(offline: !online);
    });
    return ChatState(offline: !ref.read(connectivityProvider));
  }

  void startNew() {
    _cancel?.cancel('new');
    _cancel = null;
    _fresh = true;
    state = ChatState(offline: !ref.read(connectivityProvider));
  }

  Future<void> hydrate(String? chatId) async {
    final cache = ref.read(localCacheProvider);
    if (chatId == null) {
      _fresh = false;
      return;
    }
    var local = [
      for (final row in await cache.messagesFor(chatId)) ChatMessage.fromJson(row),
    ];
    final remoteId = apiChatId(chatId);
    state = ChatState(
      chatId: chatId,
      messages: local,
      offline: !ref.read(connectivityProvider),
    );
    if (remoteId == null) return;
    try {
      final remote = await ref.read(chatRepositoryProvider).loadMessages(remoteId);
      if (remote.isNotEmpty) {
        local = _merge(local, remote);
        await cache.replaceMessagesFor(remoteId, [
          for (final m in local) m.copyWith(chatRemoteId: remoteId).toJson(),
        ]);
      }
      state = ChatState(chatId: remoteId, messages: local, offline: false);
    } catch (_) {
      state = state.copyWith(offline: true);
    }
  }

  /// Server history is source of truth. Drop optimistic `local_*` rows that
  /// match a remote message (same role + text) so the question isn't shown twice.
  List<ChatMessage> _merge(List<ChatMessage> local, List<ChatMessage> remote) {
    if (remote.isEmpty) return local;
    final remoteIds = <String>{
      for (final m in remote) ...[m.id, if (m.remoteId != null) m.remoteId!],
    };
    bool taken(ChatMessage r, ChatMessage l) {
      if (r.role != l.role) return false;
      return r.content.trim() == l.content.trim();
    }

    final extra = <ChatMessage>[];
    for (final m in local) {
      final ids = {m.id, if (m.remoteId != null) m.remoteId!};
      if (ids.any(remoteIds.contains)) continue;
      if (!m.queued && remote.any((r) => taken(r, m))) continue;
      extra.add(m);
    }
    final out = [...remote, ...extra]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  void setPinned(bool pinned) => state = state.copyWith(pinnedToBottom: pinned);

  Future<void> cancel() async {
    _cancel?.cancel('user');
    _cancel = null;
    if (!state.streaming) return;
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && msgs.last.isAssistant && msgs.last.streaming) {
      msgs[msgs.length - 1] = msgs.last.copyWith(streaming: false, failed: true);
    }
    state = state.copyWith(messages: msgs, streaming: false);
  }

  Future<void> regenerate() async {
    ChatMessage? user;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].isUser) {
        user = state.messages[i];
        break;
      }
    }
    if (user == null) return;
    await send(user.content, retryKey: _uuid.v4(), replaceFailed: true);
  }

  Future<void> retryLast() async {
    ChatMessage? failed;
    ChatMessage? user;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      final m = state.messages[i];
      if (failed == null && m.isAssistant && (m.failed || m.queued || m.content.isEmpty)) {
        failed = m;
        continue;
      }
      if (failed != null && m.isUser) {
        user = m;
        break;
      }
    }
    if (user == null) return;
    final key = failed?.idempotencyKey ?? user.idempotencyKey;
    await send(user.content, retryKey: key, replaceFailed: true);
  }

  Future<bool> send(
    String raw, {
    String? retryKey,
    bool replaceFailed = false,
    bool fromQueue = false,
    String? preferChatId,
  }) async {
    final query = raw.trim();
    if (query.isEmpty || state.streaming) return false;
    final key = retryKey ?? _uuid.v4();
    final now = DateTime.now().toUtc();
    final online = ref.read(connectivityProvider);

    if (preferChatId != null && preferChatId.isNotEmpty && preferChatId != state.chatId) {
      await hydrate(preferChatId);
    }

    var msgs = [...state.messages];
    final hasUser = msgs.any((m) => m.isUser && m.idempotencyKey == key);
    if (replaceFailed) {
      msgs.removeWhere(
        (m) => m.isAssistant && m.idempotencyKey == key && (m.queued || m.failed || m.streaming || m.content.isEmpty),
      );
      if (msgs.isNotEmpty && msgs.last.isAssistant && (msgs.last.queued || msgs.last.failed)) {
        msgs.removeLast();
      }
    }
    if (!hasUser && !replaceFailed) {
      msgs.add(
        ChatMessage(
          id: 'local_${_uuid.v4()}',
          chatRemoteId: state.chatId,
          role: 'user',
          content: query,
          idempotencyKey: key,
          createdAt: now,
        ),
      );
    } else if (!hasUser && replaceFailed) {
      // Drain of a thread that isn't in memory — keep the user row.
      msgs.add(
        ChatMessage(
          id: 'local_${_uuid.v4()}',
          chatRemoteId: state.chatId,
          role: 'user',
          content: query,
          idempotencyKey: key,
          createdAt: now,
        ),
      );
    }

    if (!online && !fromQueue) {
      await _enqueue(query: query, key: key, msgs: msgs, now: now);
      return true;
    }
    if (!online && fromQueue) {
      return false;
    }

    final asstId = 'local_${_uuid.v4()}';
    msgs.add(
      ChatMessage(
        id: asstId,
        chatRemoteId: state.chatId,
        role: 'assistant',
        content: '',
        streaming: true,
        idempotencyKey: key,
        createdAt: now.add(const Duration(milliseconds: 1)),
      ),
    );
    state = state.copyWith(messages: msgs, streaming: true, offline: false);
    final userRow = msgs.lastWhere((m) => m.isUser && m.idempotencyKey == key, orElse: () => msgs[msgs.length - 2]);
    await ref.read(localCacheProvider).upsertMessageJson(userRow.toJson());

    _cancel = CancelToken();
    try {
      StreamAsk? last;
      await for (final snap in ref.read(chatRepositoryProvider).askStream(
            query: query,
            chatId: apiChatId(state.chatId),
            idempotencyKey: key,
            cancelToken: _cancel,
          )) {
        last = snap;
        final copy = [...state.messages];
        final i = copy.indexWhere((m) => m.id == asstId);
        if (i < 0) break;
        copy[i] = copy[i].copyWith(
          content: snap.answer,
          citations: snap.citations,
          degraded: snap.degraded,
          streaming: true,
          queued: false,
          chatRemoteId: snap.chatId,
          remoteId: snap.messageId,
          mode: snap.mode,
          promptTokens: snap.promptTokens,
          completionTokens: snap.completionTokens,
          latencyMs: snap.latencyMs,
        );
        if (i > 0 && copy[i - 1].isUser) {
          copy[i - 1] = copy[i - 1].copyWith(chatRemoteId: snap.chatId);
        }
        state = state.copyWith(
          messages: copy,
          chatId: snap.chatId.isEmpty ? state.chatId : snap.chatId,
          degraded: snap.degraded,
        );
      }
      final copy = [...state.messages];
      final i = copy.indexWhere((m) => m.id == asstId);
      if (i >= 0) {
        copy[i] = copy[i].copyWith(streaming: false, failed: last == null, queued: false);
        state = state.copyWith(messages: copy, streaming: false, degraded: copy[i].degraded);
        await ref.read(localCacheProvider).upsertMessageJson(copy[i].toJson());
        if (i > 0 && copy[i - 1].isUser) {
          await ref.read(localCacheProvider).upsertMessageJson(copy[i - 1].toJson());
        }
        if (state.chatId != null) {
          await ref.read(localCacheProvider).upsertThread(
                remoteId: state.chatId!,
                title: query,
              );
        }
      } else {
        state = state.copyWith(streaming: false);
      }
      return last != null;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return false;
      }
      if (ConnectivityNotifier.isOfflineDio(e) && !fromQueue) {
        await _enqueue(query: query, key: key, msgs: [...state.messages]..removeWhere((m) => m.id == asstId), now: now);
        return true;
      }
      final copy = [...state.messages];
      final i = copy.indexWhere((m) => m.id == asstId);
      if (i >= 0) {
        copy[i] = copy[i].copyWith(streaming: false, failed: true, queued: false);
      }
      state = state.copyWith(
        messages: copy,
        streaming: false,
        offline: ConnectivityNotifier.isOfflineDio(e),
      );
      return false;
    } catch (_) {
      final copy = [...state.messages];
      final i = copy.indexWhere((m) => m.id == asstId);
      if (i >= 0) {
        copy[i] = copy[i].copyWith(streaming: false, failed: true, queued: false);
      }
      state = state.copyWith(messages: copy, streaming: false);
      return false;
    }
  }

  Future<void> _enqueue({
    required String query,
    required String key,
    required List<ChatMessage> msgs,
    required DateTime now,
  }) async {
    var threadId = state.chatId;
    if (threadId == null || threadId.isEmpty) {
      threadId = 'local_${_uuid.v4()}';
    }
    msgs = [
      for (final m in msgs)
        if (m.chatRemoteId == null) m.copyWith(chatRemoteId: threadId) else m,
    ];
    if (msgs.isEmpty || !msgs.last.isAssistant || msgs.last.idempotencyKey != key) {
      msgs.add(
        ChatMessage(
          id: 'local_${_uuid.v4()}',
          chatRemoteId: threadId,
          role: 'assistant',
          content: 'Queued — will send when you’re back online.',
          queued: true,
          idempotencyKey: key,
          createdAt: now.add(const Duration(milliseconds: 1)),
        ),
      );
    } else {
      msgs[msgs.length - 1] = msgs.last.copyWith(
        content: 'Queued — will send when you’re back online.',
        queued: true,
        failed: false,
        streaming: false,
        chatRemoteId: threadId,
      );
    }
    final cache = ref.read(localCacheProvider);
    await cache.enqueueOutbox({
      'id': key,
      'kind': 'ask',
      'query': query,
      'chatId': threadId,
      'idempotencyKey': key,
      'createdAt': now.toIso8601String(),
    });
    await cache.upsertThread(remoteId: threadId, title: query);
    for (final m in msgs.where((m) => m.idempotencyKey == key)) {
      await cache.upsertMessageJson(m.copyWith(chatRemoteId: threadId).toJson());
    }
    ref.read(outboxTickProvider.notifier).state++;
    state = state.copyWith(
      chatId: threadId,
      messages: msgs,
      streaming: false,
      offline: true,
    );
  }
}
