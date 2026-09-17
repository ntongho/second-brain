import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/library/data/library_repository.dart';
import 'package:second_brain/features/library/domain/library_doc.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.asPanel = false});

  final bool asPanel;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  List<LibraryDoc>? _docs;
  List<SearchHit> _hits = const [];
  Object? _error;
  var _loading = true;
  var _grid = false;
  String _filter = 'all';
  String? _tag;
  String _range = 'any'; // any | 7d | 30d
  final _query = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  DateTime? get _from {
    final now = DateTime.now().toUtc();
    if (_range == '7d') return now.subtract(const Duration(days: 7));
    if (_range == '30d') return now.subtract(const Duration(days: 30));
    return null;
  }

  String? get _fromIso => _from?.toIso8601String();

  Future<void> _reload() async {
    setState(() {
      _loading = _docs == null;
      _error = null;
    });
    try {
      final rows = await ref.read(libraryRepositoryProvider).list(force: true);
      if (!mounted) return;
      setState(() {
        _docs = rows;
        _loading = false;
      });
      await _runSearch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _runSearch);
    setState(() {});
  }

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.length < 2) {
      if (_hits.isNotEmpty) setState(() => _hits = const []);
      return;
    }
    try {
      final hits = await ref.read(libraryRepositoryProvider).search(
            q: q,
            sourceType: _filter == 'all' ? null : _filter,
            tag: _tag,
            from: _fromIso,
          );
      if (!mounted) return;
      setState(() => _hits = hits);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hits = const []);
    }
  }

  List<LibraryDoc> get _visible {
    final q = _query.text.trim().toLowerCase();
    final from = _from;
    var rows = [
      for (final d in _docs ?? const <LibraryDoc>[])
        if ((_filter == 'all' || d.sourceType == _filter) &&
            (_tag == null || d.tags.map((t) => t.toLowerCase()).contains(_tag!.toLowerCase())) &&
            (from == null || !d.createdAt.isBefore(from)))
          d,
    ];
    if (q.length >= 2 && _hits.isNotEmpty) {
      final byId = {for (final d in rows) d.id: d};
      final ordered = <LibraryDoc>[];
      final seen = <String>{};
      for (final h in _hits) {
        if (!seen.add(h.documentId)) continue;
        final d = byId[h.documentId];
        if (d != null) ordered.add(d);
      }
      return ordered;
    }
    if (q.isEmpty) return rows;
    return [
      for (final d in rows)
        if (d.title.toLowerCase().contains(q) || d.tags.any((t) => t.toLowerCase().contains(q))) d,
    ];
  }

  List<String> get _allTags {
    final set = <String>{};
    for (final d in _docs ?? const <LibraryDoc>[]) {
      set.addAll(d.tags);
    }
    final out = set.toList()..sort();
    return out;
  }

  Future<void> _delete(LibraryDoc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from library?'),
        content: Text('“${doc.title}” will be removed. Chat won’t cite it anymore.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final previous = _docs;
    setState(() => _docs = [...?_docs]..removeWhere((d) => d.id == doc.id));
    try {
      await ref.read(libraryRepositoryProvider).delete(doc.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _docs = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _rename(LibraryDoc doc) async {
    final ctl = TextEditingController(text: doc.title);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (next == null || next.isEmpty || next == doc.title) return;
    try {
      final updated = await ref.read(libraryRepositoryProvider).patch(doc.id, title: next);
      setState(() {
        _docs = [
          for (final d in _docs ?? const <LibraryDoc>[])
            if (d.id == doc.id) updated else d,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _retag(LibraryDoc doc) async {
    final ctl = TextEditingController(text: doc.tags.join(', '));
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tags'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Comma-separated tags', hintText: 'finance, invoice'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (next == null) return;
    final tags = [
      for (final p in next.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    try {
      final updated = await ref.read(libraryRepositoryProvider).patch(doc.id, tags: tags);
      setState(() {
        _docs = [
          for (final d in _docs ?? const <LibraryDoc>[])
            if (d.id == doc.id) updated else d,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _add() async {
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
    if (!mounted) return;
    if (choice == 'text') await context.push('/ingest/text');
    if (choice == 'pdf') await context.push('/ingest/pdf');
    if (choice == 'voice') await context.push('/ingest/voice');
    if (mounted) _reload();
  }

  void _open(LibraryDoc d, {String? highlight}) {
    final router = GoRouter.of(context);
    if (widget.asPanel) Navigator.pop(context);
    final q = highlight == null ? '' : '?highlight=${Uri.encodeComponent(highlight)}';
    router.push('/doc/${d.id}$q');
  }

  IconData _iconFor(LibraryDoc d) {
    if (d.sourceType == 'pdf') return Icons.picture_as_pdf;
    if (d.sourceType == 'voice') return Icons.mic;
    return Icons.notes;
  }

  String _badge(LibraryDoc d) {
    if (d.sourceType == 'pdf') return 'PDF';
    if (d.sourceType == 'voice') return 'Voice';
    return 'Note';
  }

  String? _snippet(LibraryDoc d) {
    for (final h in _hits) {
      if (h.documentId == d.id && h.snippet.trim().isNotEmpty) return h.snippet;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final tags = _allTags;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: widget.asPanel ? 'Close' : 'Back to chat',
          onPressed: () {
            if (widget.asPanel) {
              Navigator.pop(context);
            } else {
              context.go('/chat');
            }
          },
          icon: Icon(widget.asPanel ? Icons.close : Icons.arrow_back),
        ),
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: _grid ? 'List' : 'Grid',
            onPressed: () => setState(() => _grid = !_grid),
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
          ),
          IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add',
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Couldn’t reach the library. Open it once while online to read it offline.\n\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: TextField(
                        controller: _query,
                        onChanged: _onQuery,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search your library',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final e in const [
                            ('all', 'All'),
                            ('pdf', 'PDFs'),
                            ('text', 'Notes'),
                            ('voice', 'Voice'),
                          ])
                            FilterChip(
                              label: Text(e.$2),
                              selected: _filter == e.$1,
                              onSelected: (_) {
                                setState(() => _filter = e.$1);
                                _runSearch();
                              },
                            ),
                          for (final e in const [
                            ('any', 'Any time'),
                            ('7d', 'Last 7 days'),
                            ('30d', 'Last 30 days'),
                          ])
                            FilterChip(
                              label: Text(e.$2),
                              selected: _range == e.$1,
                              onSelected: (_) {
                                setState(() => _range = e.$1);
                                _runSearch();
                              },
                            ),
                          for (final t in tags.take(12))
                            FilterChip(
                              label: Text(t),
                              selected: _tag == t,
                              onSelected: (_) {
                                setState(() => _tag = _tag == t ? null : t);
                                _runSearch();
                              },
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: (_docs == null || _docs!.isEmpty)
                          ? const Center(child: Text('Nothing in your library yet. Tap + to add a note or PDF.'))
                          : rows.isEmpty
                              ? const Center(child: Text('No documents match that filter.'))
                              : RefreshIndicator(
                                  onRefresh: _reload,
                                  child: _grid ? _gridView(rows) : _listView(rows),
                                ),
                    ),
                  ],
                ),
    );
  }

  Widget _listView(List<LibraryDoc> rows) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _listCard(rows[i]),
    );
  }

  Widget _gridView(List<LibraryDoc> rows) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => _gridCard(rows[i]),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(LibraryDoc d) => [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'tags', child: Text('Tags')),
        if (d.sourceType == 'text') const PopupMenuItem(value: 'edit', child: Text('Edit note')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ];

  Future<void> _onMenu(String v, LibraryDoc d) async {
    if (v == 'open') _open(d);
    if (v == 'rename') await _rename(d);
    if (v == 'tags') await _retag(d);
    if (v == 'edit') {
      await context.push('/ingest/text?id=${Uri.encodeComponent(d.id)}');
      if (mounted) _reload();
    }
    if (v == 'delete') _delete(d);
  }

  Widget _gridCard(LibraryDoc d) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: SbTokens.primary.withValues(alpha: 0.2),
                    child: Icon(_iconFor(d), size: 18, color: SbTokens.primary),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) => _onMenu(v, d),
                    itemBuilder: (ctx) => _menuItems(d),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  d.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                [
                  _badge(d),
                  if (d.tags.isNotEmpty) d.tags.take(2).join(', '),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listCard(LibraryDoc d) {
    final snip = _snippet(d);
    return Card(
      child: ListTile(
        onTap: () => _open(d),
        title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          snip ?? '${_badge(d)} · ${d.status}${d.tags.isEmpty ? '' : ' · ${d.tags.join(', ')}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        leading: CircleAvatar(
          backgroundColor: SbTokens.primary.withValues(alpha: 0.2),
          child: Icon(_iconFor(d), color: SbTokens.primary),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onMenu(v, d),
          itemBuilder: (ctx) => _menuItems(d),
        ),
      ),
    );
  }
}
