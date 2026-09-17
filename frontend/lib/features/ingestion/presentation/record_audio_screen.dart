import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/ingestion/data/ingest_repository.dart';
import 'package:second_brain/features/ingestion/data/memo_recorder.dart';
import 'package:second_brain/features/ingestion/data/pick_bytes.dart';
import 'package:second_brain/features/ingestion/presentation/duplicate.dart';
import 'package:second_brain/features/ingestion/presentation/widgets/audio_waveform.dart';
import 'package:second_brain/features/library/data/library_repository.dart';
import 'package:second_brain/features/library/domain/library_doc.dart';
import 'package:second_brain/features/viewer/presentation/widgets/voice_player.dart';

class RecordAudioScreen extends ConsumerStatefulWidget {
  const RecordAudioScreen({super.key});

  @override
  ConsumerState<RecordAudioScreen> createState() => _RecordAudioScreenState();
}

class _RecordAudioScreenState extends ConsumerState<RecordAudioScreen> {
  MemoRecorder? _rec;
  StreamSubscription<double>? _ampSub;
  Timer? _tick;

  DateTime? _started;
  var _elapsed = 0.0;
  var _recording = false;
  var _denied = false;
  var _busy = false;
  String? _error;
  String? _hint;

  Uint8List? _bytes;
  LibraryDoc? _appendTo;
  String _filename = 'memo.webm';
  String _phase = '';
  double _progress = 0;
  CancelToken? _cancel;

  final _levels = List<double>.filled(28, 0.08);
  var _peak = 0.0;
  late final TextEditingController _title;

  static const _cap = 10 * 60;
  static const _minSeconds = 1.5;
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _stampTitle());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ampSub?.cancel();
    _cancel?.cancel('leave');
    _rec?.dispose();
    _title.dispose();
    super.dispose();
  }

  String _stampTitle() {
    final n = DateTime.now();
    final hh = n.hour.toString().padLeft(2, '0');
    final mm = n.minute.toString().padLeft(2, '0');
    return 'Voice memo · ${n.day} ${_months[n.month - 1]} ${n.year}, $hh:$mm';
  }

  String _stem(String name) {
    final base = name.split('/').last.split('\\').last;
    final i = base.lastIndexOf('.');
    return (i <= 0 ? base : base.substring(0, i)).replaceAll('_', ' ').replaceAll('-', ' ');
  }

  String _clock(double s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).floor().toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _hint = null;
      _denied = false;
      _bytes = null;
      _peak = 0;
      for (var i = 0; i < _levels.length; i++) {
        _levels[i] = 0.08;
      }
    });
    final rec = MemoRecorder();
    _rec = rec;
    try {
      await rec.start();
    } on MemoRecorderPermission {
      setState(() {
        _denied = true;
        _error = 'Microphone is blocked. Allow it for this site, or pick an audio file.';
      });
      return;
    } catch (e) {
      setState(() {
        _denied = true;
        _error = 'Could not start the microphone. $e';
      });
      return;
    }
    _started = DateTime.now();
    _elapsed = 0;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final s = DateTime.now().difference(_started!).inMilliseconds / 1000.0;
      if (s >= _cap) {
        _stop();
        return;
      }
      if (!mounted) return;
      setState(() {
        _elapsed = s;
        if (_peak < 0.06) {
          final t = s * 8;
          for (var i = 0; i < _levels.length; i++) {
            _levels[i] = 0.16 + 0.28 * (0.5 + 0.5 * math.sin(t + i * 0.45)).abs();
          }
        }
      });
    });
    await _ampSub?.cancel();
    _ampSub = rec.levels.listen((n) {
      if (!mounted) return;
      setState(() {
        _peak = n > _peak ? n : _peak * 0.96;
        _levels.removeAt(0);
        _levels.add(n.clamp(0.0, 1.0));
      });
    });
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stop() async {
    _tick?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    ({Uint8List bytes, String filename})? take;
    try {
      take = await _rec?.stop();
    } catch (e) {
      take = null;
      _error = 'Could not finish the recording ($e).';
    }
    if (!mounted) return;
    final bytes = take?.bytes;
    final short = _elapsed < _minSeconds;
    final tiny = bytes != null && bytes.length < 2500;
    setState(() {
      _recording = false;
      if (take != null) _filename = take.filename;
      _bytes = bytes;
      if (bytes == null) {
        _error ??= 'Nothing was captured. Allow the mic, speak, then stop — or pick a file.';
      } else if (short || tiny) {
        _hint = 'That take was too short. Record at least a couple of seconds.';
        _bytes = null;
      } else {
        _hint = 'Name it, play it back, then add it to the library.';
        if (_title.text.trim().isEmpty || _title.text.startsWith('Voice memo ·')) {
          _title.text = _stampTitle();
        }
      }
    });
  }

  Future<void> _discard() async {
    setState(() {
      _bytes = null;
      _elapsed = 0;
      _hint = null;
      _error = null;
      _peak = 0;
    });
  }

  Future<void> _pick() async {
    final picked = await pickBytes(
      extensions: const ['wav', 'mp3', 'm4a', 'webm', 'ogg'],
    );
    if (picked == null) return;
    final bytes = picked.bytes;
    if (bytes.length > 25 * 1024 * 1024) {
      setState(() => _error = 'Max size is 25MB.');
      return;
    }
    setState(() {
      _denied = false;
      _error = null;
      _hint = 'File ready: ${picked.name}';
      _bytes = bytes;
      _filename = picked.name;
      _title.text = _stem(picked.name);
      _elapsed = 0;
    });
  }

  Future<void> _pickAppendNote() async {
    final rows = await ref.read(libraryRepositoryProvider).list();
    final notes = [for (final d in rows) if (d.sourceType == 'text') d];
    if (!mounted) return;
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pasted notes yet. Add a text note first, or keep this as a new memo.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<LibraryDoc>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Append transcript to…')),
            ListTile(
              title: const Text('Keep as a new voice memo'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            for (final d in notes)
              ListTile(
                title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _appendTo = picked);
  }

  Future<void> _afterTranscribed(String voiceId) async {
    final lib = ref.read(libraryRepositoryProvider);
    final voice = await lib.get(voiceId);
    final transcript = (voice.text ?? '').trim();
    var target = _appendTo;

    if (target == null && transcript.length >= 12) {
      final q = transcript.split(RegExp(r'\s+')).where((w) => w.length > 2).take(10).join(' ');
      if (q.length >= 8) {
        try {
          final hits = await lib.search(q: q, sourceType: 'text');
          SearchHit? found;
          for (final h in hits) {
            if (h.documentId != voiceId) {
              found = h;
              break;
            }
          }
          final hit = found;
          if (hit != null && mounted) {
            final go = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Add to an existing note?'),
                content: Text('This sounds related to “${hit.title}”. Append the transcript there?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep as new')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Append')),
                ],
              ),
            );
            if (go == true) {
              final rows = await lib.list();
              for (final d in rows) {
                if (d.id == hit.documentId) target = d;
              }
              target ??= LibraryDoc(
                id: hit.documentId,
                title: hit.title,
                sourceType: 'text',
                status: 'ready',
                createdAt: DateTime.now().toUtc(),
              );
            }
          }
        } catch (_) {}
      }
    }

    if (target != null && transcript.isNotEmpty) {
      final dest = await lib.get(target.id);
      final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ');
      final merged = '${(dest.text ?? '').trim()}\n\n--- Voice · ${voice.title} · $stamp UTC ---\n$transcript'.trim();
      final saved = await lib.patch(target.id, text: merged);
      try {
        await lib.delete(voiceId);
      } catch (_) {}
      if (saved.jobId != null) {
        final repo = ref.read(ingestRepositoryProvider);
        for (var i = 0; i < 80; i++) {
          final job = await repo.job(saved.jobId!);
          if (job.status == 'done' || job.status == 'failed') break;
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
      if (mounted) context.go('/doc/${target.id}');
      return;
    }
    if (mounted) context.go('/doc/$voiceId');
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _phase = 'Uploading ${(_bytes!.length / 1024).toStringAsFixed(0)} KB';
      _progress = 0;
    });
    try {
      final accepted = await ref.read(libraryRepositoryProvider).ingestAudio(
            filename: _filename,
            bytes: bytes,
            title: _title.text.trim().isEmpty ? _stampTitle() : _title.text.trim(),
            durationSeconds: _elapsed >= _minSeconds ? _elapsed : null,
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
        _phase = 'Transcribing…';
        _progress = 0.15;
      });
      final repo = ref.read(ingestRepositoryProvider);
      var status = 'queued';
      String? jobErr;
      for (var i = 0; i < 180; i++) {
        if (_cancel?.isCancelled == true) return;
        final job = await repo.job(accepted.jobId);
        status = job.status;
        jobErr = job.error;
        if (!mounted) return;
        setState(() {
          _progress = status == 'done' ? 1 : (0.15 + job.progress.clamp(0, 1) * 0.85);
          if (status == 'processing') _phase = 'Transcribing with Whisper…';
        });
        if (status == 'done' || status == 'failed') break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!mounted) return;
      if (status != 'done') {
        setState(() => _error = jobErr ?? 'Transcription failed. Try a longer, clearer take.');
        return;
      }
      await _afterTranscribed(accepted.documentId);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        setState(() => _error = 'Cancelled.');
        return;
      }
      setState(() => _error = e.message ?? 'Network error');
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
  Widget build(BuildContext context) {
    final reviewing = _bytes != null && !_recording;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            _cancel?.cancel('back');
            if (_recording) _stop();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/library');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_recording ? 'Listening…' : reviewing ? 'Review take' : 'Voice memo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _recording
                ? 'Speak now. The bar fills as time passes. Tap the red button to stop.'
                : reviewing
                    ? 'Play it back. If it’s you, add it to the library.'
                    : 'Tap the amber mic, allow the browser if asked, then speak. Max 10 minutes.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          AudioWaveform(levels: _levels, active: _recording),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _recording || reviewing ? _clock(_elapsed) : '00:00',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: _recording ? SbTokens.danger : SbTokens.audio,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ((_recording ? _elapsed : 0) / _cap).clamp(0, 1),
              minHeight: 12,
              color: _recording ? SbTokens.danger : SbTokens.audio,
              backgroundColor: const Color(0x33F59E0B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _recording
                ? 'Recorded ${_clock(_elapsed)} of 10:00'
                : reviewing
                    ? 'Take ${_clock(_elapsed)}  ·  ${(_bytes!.length / 1024).toStringAsFixed(0)} KB'
                    : '0:00 of 10:00 max',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  _peak < 0.08 ? 'Can’t hear you — move closer to the mic' : 'Hearing you',
                  style: TextStyle(color: _peak < 0.08 ? SbTokens.danger : SbTokens.success),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: _busy
                  ? null
                  : () {
                      if (_recording) {
                        _stop();
                      } else if (!reviewing) {
                        _start();
                      }
                    },
              child: SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 108,
                      height: 108,
                      child: CircularProgressIndicator(
                        value: _recording ? (_elapsed / _cap).clamp(0.0, 1.0) : 0,
                        strokeWidth: 6,
                        color: SbTokens.danger,
                        backgroundColor: const Color(0x33F59E0B),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recording ? SbTokens.danger : SbTokens.audio,
                      ),
                      child: Icon(
                        _recording ? Icons.stop_rounded : Icons.mic,
                        size: 40,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _recording
                  ? 'Tap to stop'
                  : reviewing
                      ? ''
                      : 'Tap to record',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_denied) ...[
            const SizedBox(height: 16),
            const Text(
              'Microphone is blocked. Allow it for this site (lock icon in the address bar), or pick an audio file.',
            ),
          ],
          const SizedBox(height: 20),
          if (!reviewing && !_recording)
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('Or pick an audio file'),
            ),
          if (reviewing) ...[
            VoicePlayer(bytes: _bytes!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickAppendNote,
              icon: const Icon(Icons.note_add_outlined),
              label: Text(_appendTo == null ? 'Append to an existing note' : 'Will append to: ${_appendTo!.title}'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _busy ? null : _discard, child: const Text('Discard')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _upload,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Add to library'),
                  ),
                ),
              ],
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            Text(_phase),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress <= 0 ? null : _progress, color: SbTokens.audio, minHeight: 8),
          ],
          if (_hint != null) ...[
            const SizedBox(height: 16),
            Text(_hint!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.danger)),
          ],
        ],
      ),
    );
  }
}
