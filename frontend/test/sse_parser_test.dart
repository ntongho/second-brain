import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/network/sse.dart';

void main() {
  test('parses meta/token/done and ignores ping comments', () async {
    final raw = [
      ':ping',
      '',
      'event: meta',
      'data: {"chat_id":"chat_1","message_id":"msg_1","degraded":false}',
      '',
      'event: token',
      'data: {"delta":"Hello"}',
      '',
      'event: token',
      'data: {"delta":" world"}',
      '',
      'event: done',
      'data: {"mode":"full"}',
      '',
    ];
    final events = await parseSse(Stream.fromIterable(raw)).toList();
    expect(events.map((e) => e.event).toList(), ['meta', 'token', 'token', 'done']);
    expect(events[1].data, contains('Hello'));
    expect(events[2].data, contains('world'));
  });
}
