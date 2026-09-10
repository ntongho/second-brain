import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:second_brain/core/network/connectivity.dart';
import 'package:second_brain/core/storage/local_cache.dart';
import 'package:second_brain/features/chat/application/chat_controller.dart';

class SyncState {
  const SyncState({this.pending = 0, this.draining = false});

  final int pending;
  final bool draining;

  String? get banner {
    if (draining && pending > 0) {
      return 'Syncing $pending queued ${pending == 1 ? 'question' : 'questions'}…';
    }
    if (!draining && pending > 0) {
      return '$pending queued — will send when you’re online';
    }
    return null;
  }
}

final syncQueueProvider = NotifierProvider<SyncQueueNotifier, SyncState>(SyncQueueNotifier.new);

class SyncQueueNotifier extends Notifier<SyncState> {
  var _busy = false;

  @override
  SyncState build() {
    ref.listen<int>(outboxTickProvider, (_, __) {
      _refreshCount();
    });
    ref.listen<bool>(connectivityProvider, (prev, online) {
      if (online) drain();
    });
    Future.microtask(_refreshCount);
    return const SyncState();
  }

  Future<void> _refreshCount() async {
    final n = (await ref.read(localCacheProvider).pendingOutbox()).length;
    state = SyncState(pending: n, draining: state.draining);
  }

  Future<void> drain() async {
    if (_busy) return;
    if (!ref.read(connectivityProvider)) return;
    _busy = true;
    state = SyncState(pending: state.pending, draining: true);
    try {
      final cache = ref.read(localCacheProvider);
      final items = await cache.pendingOutbox();
      for (final item in items) {
        if (!ref.read(connectivityProvider)) break;
        while (ref.read(chatProvider).streaming) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!ref.read(connectivityProvider)) break;
        }
        if (item['kind'] != 'ask') continue;
        final query = item['query'] as String? ?? '';
        final key = item['idempotencyKey'] as String? ?? item['id'] as String? ?? '';
        if (query.isEmpty || key.isEmpty) {
          await cache.removeOutbox(item['id'] as String);
          continue;
        }
        final chatId = item['chatId'] as String?;
        final ok = await ref.read(chatProvider.notifier).send(
              query,
              retryKey: key,
              replaceFailed: true,
              fromQueue: true,
              preferChatId: chatId,
            );
        if (ok) {
          await cache.removeOutbox(item['id'] as String);
        } else {
          break;
        }
      }
    } finally {
      _busy = false;
      await _refreshCount();
      state = SyncState(pending: state.pending, draining: false);
    }
  }
}
