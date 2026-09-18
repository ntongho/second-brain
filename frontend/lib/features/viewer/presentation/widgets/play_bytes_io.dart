import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

String _ext(String type) {
  if (type.contains('wav')) return 'wav';
  if (type.contains('mpeg') || type.contains('mp3')) return 'mp3';
  if (type.contains('ogg')) return 'ogg';
  if (type.contains('webm')) return 'webm';
  if (type.contains('aac')) return 'aac';
  return 'm4a';
}

/// ExoPlayer on Android rejects in-memory StreamAudioSource for wav/m4a ("Source error").
Future<Future<void> Function()> loadPlayable(
  AudioPlayer player,
  Uint8List bytes,
  String contentType,
) async {
  final dir = Directory.systemTemp;
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final f = File('${dir.path}${Platform.pathSeparator}sb_play_${DateTime.now().microsecondsSinceEpoch}.${_ext(contentType)}');
  await f.writeAsBytes(bytes, flush: true);
  await player.setFilePath(f.path);
  return () async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  };
}
