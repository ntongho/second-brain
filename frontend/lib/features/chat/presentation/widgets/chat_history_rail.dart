import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/storage/local_cache.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/auth/application/auth_controller.dart';
import 'package:second_brain/features/chat/application/chat_controller.dart';
import 'package:second_brain/features/chat/data/chat_repository.dart';

typedef _ChatRow = ({String id, String title, DateTime createdAt});

class ChatHistoryRail extends ConsumerStatefulWidget {
  const ChatHistoryRail({super.key, this.onPicked});

  final VoidCallback? onPicked;

  @override
  ConsumerState<ChatHistoryRail> createState() => _ChatHistoryRailState();
}

class _ChatHistoryRailState extends ConsumerState<ChatHistoryRail> {
  final _search = TextEditingController();
  List<_ChatRow>? _rows;
  Object? _error;
  var _loading = true;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cached = await ref.read(localCacheProvider).threads();
      if (mounted && cached.isNotEmpty && _rows == null) {
        setState(() {
          _rows = [
            for (final t in cached)
              (
                id: t['remoteId'] as String? ?? '',
                title: t['title'] as String? ?? 'Chat',
                createdAt: DateTime.tryParse(t['updatedAt'] as String? ?? '') ?? DateTime.now().toUtc(),
              ),
          ]..removeWhere((r) => r.id.isEmpty);
          _loading = false;
        });
      }
    } catch (_) {}
    try {
      final rows = await ref.read(chatRepositoryProvider).listChats();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _rows == null ? e : null;
        _loading = false;
      });
    }
  }

  bool _isToday(DateTime utc) {
    final d = utc.toLocal();
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _matches(_ChatRow r) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.title.toLowerCase().contains(q);
  }

  Future<void> _delete(_ChatRow c) async {
    final previous = _rows;
    setState(() => _rows = [...?_rows]..removeWhere((x) => x.id == c.id));
    try {
      await ref.read(chatRepositoryProvider).deleteChat(c.id);
      if (ref.read(chatProvider).chatId == c.id) {
        ref.read(chatProvider.notifier).startNew();
        context.go('/chat');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rows = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _rename(_ChatRow c) async {
    final ctl = TextEditingController(text: c.title);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (next == null || next.isEmpty || next == c.title) return;
    try {
      await ref.read(chatRepositoryProvider).renameChat(c.id, next);
      await ref.read(localCacheProvider).upsertThread(remoteId: c.id, title: next);
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final r in _rows ?? const <_ChatRow>[])
            if (r.id == c.id) (id: r.id, title: next, createdAt: r.createdAt) else r,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _newChat() {
    ref.read(chatProvider.notifier).startNew();
    widget.onPicked?.call();
    context.go('/chat');
  }

  void _open(_ChatRow c) {
    ref.read(chatProvider.notifier).hydrate(c.id);
    widget.onPicked?.call();
    context.go('/chat/${c.id}');
  }

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  TextStyle _navStyle(Color color) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.25,
        letterSpacing: -0.15,
        color: color,
      );

  TextStyle _histStyle(Color color) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.25,
        letterSpacing: -0.2,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(chatProvider.select((s) => s.chatId));
    ref.listen(chatProvider.select((s) => s.chatId), (prev, next) {
      if (next != null && next != prev && !next.startsWith('local_')) {
        _load();
      }
    });

    final onSurface = Theme.of(context).colorScheme.onSurface;
    final today = [
      for (final r in _rows ?? const <_ChatRow>[])
        if (_isToday(r.createdAt) && _matches(r)) r,
    ];
    final older = [
      for (final r in _rows ?? const <_ChatRow>[])
        if (!_isToday(r.createdAt) && _matches(r)) r,
    ];
    final searching = _query.trim().isNotEmpty;
    final emptyFilter = searching && today.isEmpty && older.isEmpty;

    final email = ref.watch(authProvider).asData?.value?.email ?? 'Account';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: Icon(Icons.edit_square, size: 18, color: onSurface.withValues(alpha: 0.85)),
                    title: Text('New chat', style: _navStyle(onSurface)),
                    onTap: _newChat,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      style: _histStyle(onSurface),
                      cursorColor: SbTokens.primary,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search chats',
                        hintStyle: _histStyle(onSurface.withValues(alpha: 0.45)),
                        prefixIcon: Icon(Icons.search, size: 18, color: onSurface.withValues(alpha: 0.55)),
                        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        suffixIcon: searching
                            ? IconButton(
                                tooltip: 'Clear',
                                icon: Icon(Icons.close, size: 16, color: onSurface.withValues(alpha: 0.55)),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: onSurface.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('$_error', textAlign: TextAlign.center, style: _histStyle(onSurface)))
                    : (_rows == null || _rows!.isEmpty)
                        ? Center(child: Text('No chats yet', style: _histStyle(onSurface.withValues(alpha: 0.5))))
                        : emptyFilter
                            ? Center(
                                child: Text('No matching chats', style: _histStyle(onSurface.withValues(alpha: 0.5))),
                              )
                            : ListView(
                                padding: const EdgeInsets.only(bottom: 16),
                                children: [
                                  if (today.isNotEmpty) ...[
                                    _sectionLabel(context, 'Today'),
                                    for (final c in today) _tile(c, active, onSurface),
                                  ],
                                  if (older.isNotEmpty) ...[
                                    _sectionLabel(context, 'Older'),
                                    for (final c in older) _tile(c, active, onSurface),
                                  ],
                                ],
                              ),
          ),
          Divider(height: 1, color: onSurface.withValues(alpha: 0.08)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: PopupMenuButton<String>(
                tooltip: 'Account',
                offset: const Offset(0, -8),
                position: PopupMenuPosition.over,
                onSelected: (v) {
                  if (v == 'logout') _signOut();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    enabled: false,
                    height: 36,
                    child: Text(email, style: _histStyle(onSurface.withValues(alpha: 0.55))),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Log out', style: _navStyle(onSurface)),
                  ),
                ],
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: CircleAvatar(
                    radius: 13,
                    backgroundColor: SbTokens.primary.withValues(alpha: 0.22),
                    child: Text(
                      initial,
                      style: _navStyle(onSurface).copyWith(fontSize: 12),
                    ),
                  ),
                  title: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: _navStyle(onSurface)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.2,
          letterSpacing: -0.1,
          color: muted,
        ),
      ),
    );
  }

  Widget _tile(_ChatRow c, String? active, Color onSurface) {
    final selected = c.id == active;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 14, right: 4),
      selected: selected,
      selectedTileColor: SbTokens.primary.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(
        c.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _histStyle(onSurface.withValues(alpha: selected ? 1 : 0.88)),
      ),
      onTap: () => _open(c),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz, size: 18, color: onSurface.withValues(alpha: 0.55)),
        onSelected: (v) {
          if (v == 'rename') _rename(c);
          if (v == 'delete') _delete(c);
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(value: 'rename', child: Text('Rename', style: _histStyle(onSurface))),
          PopupMenuItem(value: 'delete', child: Text('Delete', style: _histStyle(onSurface))),
        ],
      ),
    );
  }
}
