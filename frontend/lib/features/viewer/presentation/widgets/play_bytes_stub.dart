import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

Future<Future<void> Function()> loadPlayable(
  AudioPlayer player,
  Uint8List bytes,
  String contentType,
) async {
  throw UnsupportedError('audio playback');
}
