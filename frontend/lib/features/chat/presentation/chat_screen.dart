import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/connectivity.dart';
import 'package:second_brain/features/chat/application/chat_controller.dart';
import 'package:second_brain/features/chat/application/sync_queue.dart';
import 'package:second_brain/features/chat/presentation/widgets/banner_stack.dart';
import 'package:second_brain/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:second_brain/features/chat/presentation/widgets/chat_history_rail.dart';
import 'package:second_brain/features/chat/presentation/widgets/composer.dart';
import 'package:second_brain/features/chat/presentation/widgets/prompt_chips.dart';
import 'package:second_brain/features/library/presentation/library_screen.dart';
import 'package:second_brain/shared/widgets/floating_nav.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.chatId});

  final String? chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  var _userAway = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).hydrate(widget.chatId);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncQueueProvider.notifier).drain();
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final away = _scroll.position.pixels < _scroll.position.maxScrollExtent - 80;
    if (away != _userAway) {
      _userAway = away;
      ref.read(chatProvider.notifier).setPinned(!away);
    }
  }

  bool _showFollowUps(ChatState chat) {
    if (chat.streaming || chat.messages.length < 2) return false;
    final last = chat.messages.last;
    return last.isAssistant && !last.streaming && !last.failed && !last.queued;
  }

  void _maybeStick() {
    if (_userAway || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Widget _conversation(ChatState chat, bool dev, bool online) {
    return Column(
      children: [
        BannerStack(
          offline: !online || chat.offline,
          degraded: chat.degraded,
          syncLabel: ref.watch(syncQueueProvider).banner,
          queued: ref.watch(syncQueueProvider).pending,
        ),
        if (chat.streaming) const LinearProgressIndicator(minHeight: 2, color: Color(0xFF4F46E5)),
        Expanded(
          child: chat.messages.isEmpty
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Ask your library.', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          'Answers cite your notes. Empty library → “Not in your library”.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        PromptChips(onPick: (p) => ref.read(chatProvider.notifier).send(p)),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  itemCount: chat.messages.length + (_showFollowUps(chat) ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == chat.messages.length) {
                      final lastUser = chat.messages.lastWhere((m) => m.isUser, orElse: () => chat.messages.last);
                      return PromptChips(
                        prompts: followUpsFor(lastUser.content),
                        onPick: (p) => ref.read(chatProvider.notifier).send(p),
                      );
                    }
                    final m = chat.messages[i];
                    return ChatBubble(
                      message: m,
                      devMode: dev,
                      onCancel: () => ref.read(chatProvider.notifier).cancel(),
                      onRetry: () => ref.read(chatProvider.notifier).retryLast(),
                      onRegenerate: () => ref.read(chatProvider.notifier).regenerate(),
                    );
                  },
                ),
        ),
        Composer(
          enabled: true,
          streaming: chat.streaming,
          onSend: (q) => ref.read(chatProvider.notifier).send(q),
          onCancel: () => ref.read(chatProvider.notifier).cancel(),
          onAdd: () async {
            if (!online) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Need a connection to add files. Library is still readable.')),
              );
              return;
            }
            final choice = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: const Text('Paste text'),
                      onTap: () => Navigator.pop(ctx, 'text'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('Upload file'),
                      subtitle: const Text('PDF, Markdown, .txt'),
                      onTap: () => Navigator.pop(ctx, 'pdf'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.mic_none),
                      title: const Text('Record audio'),
                      onTap: () => Navigator.pop(ctx, 'voice'),
                    ),
                  ],
                ),
              ),
            );
            if (!context.mounted) return;
            if (choice == 'text') context.push('/ingest/text');
            if (choice == 'pdf') context.push('/ingest/pdf');
            if (choice == 'voice') context.push('/ingest/voice');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final dev = ref.watch(devModeProvider);
    final online = ref.watch(connectivityProvider);
    ref.listen(chatProvider, (prev, next) {
      if (next.messages.length != prev?.messages.length ||
          (next.messages.isNotEmpty && prev?.messages.last.content != next.messages.last.content)) {
        _maybeStick();
      }
    });

    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              child: ChatHistoryRail(onPicked: () => Navigator.pop(context)),
            ),
      appBar: AppBar(
        title: const Text('Second Brain'),
        actions: [
          IconButton(
            tooltip: 'Library',
            onPressed: () => showFloatingNav(context: context, child: const LibraryScreen(asPanel: true)),
            icon: const Icon(Icons.folder_outlined),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            const SizedBox(
              width: 268,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0x22FFFFFF))),
                ),
                child: ChatHistoryRail(),
              ),
            ),
          Expanded(child: _conversation(chat, dev, online)),
        ],
      ),
    );
  }
}
