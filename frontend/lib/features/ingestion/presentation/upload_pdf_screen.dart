import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/ingestion/data/ingest_repository.dart';
import 'package:second_brain/features/ingestion/data/pick_bytes.dart';
import 'package:second_brain/features/ingestion/presentation/duplicate.dart';
import 'package:second_brain/features/library/data/library_repository.dart';

class UploadPdfScreen extends ConsumerStatefulWidget {
  const UploadPdfScreen({super.key});

  @override
  ConsumerState<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends ConsumerState<UploadPdfScreen> {
  var _busy = false;
  String? _error;
  String? _name;
  String _phase = '';
  double _progress = 0;
  CancelToken? _cancel;

  Future<void> _pick() async {
    final picked = await pickBytes(
      extensions: const ['pdf', 'md', 'txt', 'text', 'markdown'],
    );
    if (picked == null) return;
    final bytes = picked.bytes;
    if (bytes.length > 25 * 1024 * 1024) {
      setState(() => _error = 'Max size is 25MB.');
      return;
    }
    _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _name = picked.name;
      _phase = 'Uploading';
      _progress = 0;
    });
    try {
      final accepted = await ref.read(libraryRepositoryProvider).ingestPdf(
            filename: picked.name,
            bytes: bytes,
            cancelToken: _cancel,
            onSendProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(() {
                _phase = 'Uploading';
                _progress = (sent / total).clamp(0, 1);
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _phase = 'Indexing';
        _progress = 0.05;
      });
      final repo = ref.read(ingestRepositoryProvider);
      var status = 'queued';
      for (var i = 0; i < 150; i++) {
        if (_cancel?.isCancelled == true) return;
        final job = await repo.job(accepted.jobId);
        status = job.status;
        if (!mounted) return;
        setState(() {
          _phase = status == 'processing' || status == 'queued' ? 'Indexing' : _phase;
          _progress = status == 'done' ? 1 : (0.15 + job.progress.clamp(0, 1) * 0.85);
        });
        if (status == 'done' || status == 'failed') break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!mounted) return;
      if (status == 'failed') {
        setState(() => _error = 'Indexing failed. Try a text-based PDF (not a scan), then retry.');
        return;
      }
      if (status != 'done') {
        setState(() => _error = 'Still indexing or the network stalled. Open Library in a few seconds.');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to your library.')));
      context.go('/library');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        setState(() => _error = 'Upload cancelled.');
        return;
      }
      setState(() => _error = e.message ?? 'Network error while uploading.');
    } on ApiException catch (e) {
      if (await showIfDuplicate(context, e)) return;
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancel?.cancel('leave');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            _cancel?.cancel('back');
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/library');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Upload file'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PDF, Markdown (.md), or text (.txt). PDFs: text-based, max 25MB / 500 pages.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _pick,
              child: Text(_name == null ? 'Choose file' : (_busy ? 'Working…' : 'Choose another file')),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              Text('$_phase${_name == null ? '' : ' · $_name'}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progress <= 0 ? null : _progress,
                color: SbTokens.primary,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              Text('${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.bodySmall),
              TextButton(
                onPressed: () => _cancel?.cancel('user'),
                child: const Text('Cancel'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
