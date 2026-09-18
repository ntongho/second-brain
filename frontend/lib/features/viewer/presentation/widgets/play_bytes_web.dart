import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class _BytesSource extends StreamAudioSource {
  _BytesSource(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: contentType,
    );
  }
}

Future<Future<void> Function()> loadPlayable(
  AudioPlayer player,
  Uint8List bytes,
  String contentType,
) async {
  await player.setAudioSource(_BytesSource(bytes, contentType));
  return () async {};
}
