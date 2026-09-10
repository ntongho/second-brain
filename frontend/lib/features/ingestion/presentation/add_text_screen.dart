import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/features/ingestion/data/ingest_repository.dart';
import 'package:second_brain/features/library/data/library_repository.dart';

class AddTextScreen extends ConsumerStatefulWidget {
  const AddTextScreen({super.key, this.docId});

  final String? docId;

  @override
  ConsumerState<AddTextScreen> createState() => _AddTextScreenState();
}

class _AddTextScreenState extends ConsumerState<AddTextScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  bool _loadingDoc = false;
  String? _error;

  bool get _editing => widget.docId != null && widget.docId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  Future<void> _load() async {
    setState(() => _loadingDoc = true);
    try {
      final doc = await ref.read(libraryRepositoryProvider).get(widget.docId!);
      if (!mounted) return;
      _title.text = doc.title;
      _body.text = doc.text ?? '';
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _waitJob(String jobId) async {
    final repo = ref.read(ingestRepositoryProvider);
    JobStatus? job;
    for (var i = 0; i < 90; i++) {
      job = await repo.job(jobId);
      if (job.status == 'done') return;
      if (job.status == 'failed') {
        throw ApiException(
          statusCode: 500,
          code: 'PROCESSING',
          message: job.error ?? 'Indexing failed',
          retryable: true,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw ApiException(
      statusCode: 504,
      code: 'TIMEOUT',
      message: 'Still indexing. Wait a few seconds, then ask again.',
      retryable: true,
    );
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final text = _body.text.trim();
    if (title.isEmpty || text.isEmpty) {
      setState(() => _error = 'Title and text are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        final saved = await ref.read(libraryRepositoryProvider).patch(
              widget.docId!,
              title: title,
              text: text,
            );
        if (saved.jobId != null) await _waitJob(saved.jobId!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note updated. Chat will use the new text.')),
        );
      } else {
        final repo = ref.read(ingestRepositoryProvider);
        final accepted = await repo.ingestText(title: title, text: text);
        await _waitJob(accepted.jobId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note is in your library. You can ask about it now.')),
        );
      }
      context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/library');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_editing ? 'Edit note' : 'Paste text'),
      ),
      body: _loadingDoc
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  enabled: !_busy,
                  minLines: 10,
                  maxLines: 20,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy || !valid ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_editing ? 'Save changes' : 'Add to library'),
                ),
              ],
            ),
    );
  }
}
