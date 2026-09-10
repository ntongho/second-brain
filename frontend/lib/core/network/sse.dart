/// SSE parser for POST /v1/ask/stream (02: meta/token/citation/done/error + :ping).
class SseEvent {
  const SseEvent(this.event, this.data);

  final String event;
  final String data;
}

Stream<SseEvent> parseSse(Stream<String> lines) async* {
  String? event;
  final data = <String>[];
  await for (var line in lines) {
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    if (line.isEmpty) {
      if (event != null || data.isNotEmpty) {
        yield SseEvent(event ?? 'message', data.join('\n'));
      }
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) {
      continue; // ping / comment
    }
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      var v = line.substring(5);
      if (v.startsWith(' ')) v = v.substring(1);
      data.add(v);
    }
  }
  if (event != null || data.isNotEmpty) {
    yield SseEvent(event ?? 'message', data.join('\n'));
  }
}
