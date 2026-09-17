import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/library/data/library_repository.dart';
import 'package:second_brain/features/library/domain/library_doc.dart';
import 'package:second_brain/features/viewer/presentation/widgets/voice_player.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({super.key, required this.docId, this.highlightChunkId});

  final String docId;
  final String? highlightChunkId;

  @override
  ConsumerState<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  LibraryDoc? _doc;
  Object? _error;
  var _loading = true;
  final _keys = <int, GlobalKey>{};
  final Map<int, Uint8List> _png = {};
  Uint8List? _audio;
  var _showTranscript = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await ref.read(libraryRepositoryProvider).get(
            widget.docId,
            highlight: widget.highlightChunkId,
          );
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
      final cited = doc.highlightPage;
      if (doc.sourceType == 'voice') {
        final bytes = await ref.read(libraryRepositoryProvider).audioBytes(doc.id);
        if (!mounted) return;
        if (bytes != null) setState(() => _audio = bytes);
      }
      if (doc.sourceType == 'pdf' && (doc.pageCount ?? 0) > 0) {
        final pages = [
          if (cited != null) cited,
          if (cited != null && cited > 1) cited - 1,
          if (cited != null && cited < (doc.pageCount ?? 0)) cited + 1,
          1,
        ];
        for (final p in pages.toSet()) {
          final bytes = await ref.read(libraryRepositoryProvider).pagePng(doc.id, p);
          if (!mounted) return;
          if (bytes != null) setState(() => _png[p] = bytes);
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final k = _keys[cited ?? 1];
        final ctx = k?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.1, duration: const Duration(milliseconds: 280));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chat');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_doc?.title ?? 'Document'),
        actions: [
          if (_doc?.sourceType == 'text')
            IconButton(
              tooltip: 'Edit note',
              onPressed: () async {
                await context.push('/ingest/text?id=${Uri.encodeComponent(widget.docId)}');
                if (mounted) _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'This document isn’t cached yet. Open it once while online.\n\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _doc!.sourceType == 'voice'
                  ? _voice()
                  : _pages(),
    );
  }

  Widget _voice() {
    final doc = _doc!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (doc.highlightSnippet != null) _citeBanner(doc),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_audio != null) VoicePlayer(bytes: _audio!) else const Text('Audio file not stored for this memo.'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showTranscript = !_showTranscript),
                  child: Text(_showTranscript ? 'Hide transcript' : 'Show transcript'),
                ),
              ),
              if (_showTranscript)
                SelectableText.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: _spans(doc.text ?? '', _findSnippet(doc.text ?? '', doc.highlightSnippet)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pages() {
    final doc = _doc!;
    final raw = doc.text ?? '';
    if (raw.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cached title only — open this document while online to store the full text.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final pages = raw.split('\f');
    final citedPage = doc.highlightPage;
    final hs = doc.highlightStart;
    final he = doc.highlightEnd;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: pages.length + (doc.highlightSnippet != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (doc.highlightSnippet != null && i == 0) {
          return _citeBanner(doc);
        }
        final pageIndex = doc.highlightSnippet != null ? i - 1 : i;
        final pageNo = pageIndex + 1;
        _keys.putIfAbsent(pageNo, GlobalKey.new);
        final fromSnippet = _findSnippet(pages[pageIndex], doc.highlightSnippet);
        final highlight = fromSnippet ?? _localHighlight(pages, pageIndex, hs, he);
        return KeyedSubtree(
          key: _keys[pageNo],
          child: _paper(
            pageNo: pageNo,
            total: pages.length,
            cited: highlight != null,
            body: pages[pageIndex],
            png: _png[pageNo],
            highlight: highlight,
          ),
        );
      },
    );
  }

  Widget _citeBanner(LibraryDoc doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x2206B6D4),
        border: Border.all(color: SbTokens.citation),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doc.highlightPage == null ? 'Cited passage' : 'Cited from page ${doc.highlightPage}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.citation),
          ),
          const SizedBox(height: 6),
          Text(doc.highlightSnippet ?? '', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _paper({
    required int pageNo,
    required int total,
    required bool cited,
    required String body,
    required Uint8List? png,
    required (int, int)? highlight,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cited ? SbTokens.citation : const Color(0xFFD6D0C4), width: cited ? 2 : 1),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page $pageNo of $total${cited ? '  ·  cited' : ''}',
            style: const TextStyle(color: Color(0xFF6B6458), fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (png != null) ...[
            Image.memory(png, fit: BoxFit.fitWidth),
            const SizedBox(height: 12),
          ],
          SelectableText.rich(
            TextSpan(
              style: const TextStyle(
                color: Color(0xFF1A1814),
                fontSize: 15,
                height: 1.45,
              ),
              children: _spans(body, highlight),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _spans(String body, (int, int)? hl) {
    if (hl == null || body.isEmpty) {
      return [TextSpan(text: body.isEmpty ? ' ' : body)];
    }
    final s = hl.$1.clamp(0, body.length);
    final e = hl.$2.clamp(0, body.length);
    if (e <= s) return [TextSpan(text: body)];
    return [
      TextSpan(text: body.substring(0, s)),
      TextSpan(
        text: body.substring(s, e),
        style: const TextStyle(
          backgroundColor: Color(0xCCFDE047),
          color: Color(0xFF1A1814),
          fontWeight: FontWeight.w600,
        ),
      ),
      TextSpan(text: body.substring(e)),
    ];
  }

  (int, int)? _findSnippet(String body, String? snippet) {
    var needle = (snippet ?? '').trim();
    if (needle.isEmpty || body.isEmpty) return null;
    var i = body.indexOf(needle);
    if (i >= 0) return (i, i + needle.length);
    if (needle.length > 96) needle = needle.substring(0, 96).trim();
    i = body.indexOf(needle);
    if (i >= 0) return (i, i + needle.length);
    final b = body.toLowerCase();
    final n = needle.toLowerCase();
    i = b.indexOf(n);
    if (i >= 0) return (i, (i + needle.length).clamp(0, body.length));
    return null;
  }

  (int, int)? _localHighlight(List<String> pages, int index, int? hs, int? he) {
    if (hs == null || he == null) return null;
    var offset = 0;
    for (var i = 0; i < pages.length; i++) {
      final start = offset;
      final end = offset + pages[i].length;
      if (i == index && he > start && hs < end) {
        return ((hs - start).clamp(0, pages[i].length), (he - start).clamp(0, pages[i].length));
      }
      offset = end + 1; // form-feed
    }
    return null;
  }
}
