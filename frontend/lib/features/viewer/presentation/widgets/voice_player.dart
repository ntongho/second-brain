import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/ingestion/presentation/widgets/audio_waveform.dart';
import 'package:second_brain/features/viewer/presentation/widgets/play_bytes.dart';

String sniffAudioContentType(Uint8List b) {
  if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
    return 'audio/wav';
  }
  if (b.length >= 4 && b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
    return 'audio/webm';
  }
  if (b.length >= 4 && b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
    return 'audio/ogg';
  }
  if (b.length >= 3 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    return 'audio/mpeg';
  }
  if (b.length >= 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    return 'audio/mp4';
  }
  if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xF0) == 0xF0) {
    return 'audio/aac';
  }
  return 'audio/mp4';
}

class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _player = AudioPlayer();
  Future<void> Function()? _cleanup;
  var _speed = 1.0;
  var _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VoicePlayer old) {
    super.didUpdateWidget(old);
    if (old.bytes != widget.bytes) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _ready = false;
      _error = null;
    });
    try {
      await _cleanup?.call();
      _cleanup = null;
      final type = widget.contentType ?? sniffAudioContentType(widget.bytes);
      _cleanup = await loadPlayable(_player, widget.bytes, type);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _cleanup?.call();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(
        'Could not play this take. Discard and record again, or add it anyway — transcription still works.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 3, color: SbTokens.audio),
      );
    }
    return StreamBuilder<Duration?>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final total = _player.duration ?? Duration.zero;
        final playing = _player.playing;
        final maxMs = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
        final value = (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AudioWaveform(
              active: playing,
              levels: [
                for (var i = 0; i < 28; i++)
                  0.15 + ((i + (pos.inMilliseconds ~/ 90)) % 7) / 10.0 * (playing ? 0.9 : 0.35),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: SbTokens.audio,
                thumbColor: SbTokens.audio,
                overlayColor: SbTokens.audio.withValues(alpha: 0.2),
                trackHeight: 4,
              ),
              child: Slider(
                value: value,
                onChanged: (v) => _player.seek(Duration(milliseconds: (v * maxMs).round())),
              ),
            ),
            Row(
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: SbTokens.audio, foregroundColor: Colors.black),
                  onPressed: () => playing ? _player.pause() : _player.play(),
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                Text('${_fmt(pos)} / ${_fmt(total)}'),
                const Spacer(),
                for (final s in [1.0, 1.5, 2.0])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text('${s}×'),
                      selected: _speed == s,
                      onSelected: (_) async {
                        setState(() => _speed = s);
                        await _player.setSpeed(s);
                      },
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
