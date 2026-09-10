import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/core/storage/local_cache.dart';

void main() {
  test('write-through and wipe leave no residue', () async {
    final mem = <String, String>{};
    final cache = LocalCache(memory: mem);
    await cache.upsertThread(remoteId: 'chat_1', title: 'Rule of 72');
    await cache.upsertMessageJson({
      'id': 'm1',
      'chatRemoteId': 'chat_1',
      'role': 'user',
      'content': 'What is the rule of 72?',
      'citations': [],
      'degraded': false,
      'failed': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    expect(await cache.messagesFor('chat_1'), hasLength(1));
    await cache.wipe();
    expect(await cache.messagesFor('chat_1'), isEmpty);
    expect(await cache.threads(), isEmpty);
    expect(await cache.documents(), isEmpty);
    expect(await cache.pendingOutbox(), isEmpty);
  });

  test('outbox upserts by idempotency key and wipe clears it', () async {
    final mem = <String, String>{};
    final cache = LocalCache(memory: mem);
    await cache.enqueueOutbox({
      'id': 'k1',
      'kind': 'ask',
      'query': 'What is the rule of 72?',
      'chatId': null,
      'idempotencyKey': 'k1',
      'createdAt': '2026-01-01T00:00:00.000Z',
    });
    await cache.enqueueOutbox({
      'id': 'k1',
      'kind': 'ask',
      'query': 'What is the rule of 72?',
      'idempotencyKey': 'k1',
      'createdAt': '2026-01-01T00:00:01.000Z',
    });
    expect(await cache.pendingOutbox(), hasLength(1));
    await cache.enqueueOutbox({
      'id': 'k2',
      'kind': 'ask',
      'query': 'Second question',
      'idempotencyKey': 'k2',
      'createdAt': '2026-01-01T00:00:02.000Z',
    });
    expect(await cache.pendingOutbox(), hasLength(2));
    await cache.removeOutbox('k1');
    expect(await cache.pendingOutbox(), hasLength(1));
    expect((await cache.pendingOutbox()).single['id'], 'k2');
    await cache.wipe();
    expect(await cache.pendingOutbox(), isEmpty);
  });

  test('document cache keeps text when list metadata overwrites', () async {
    final cache = LocalCache(memory: {});
    await cache.upsertDocuments([
      {
        'id': 'd1',
        'title': 'Note',
        'source_type': 'text',
        'status': 'ready',
        'created_at': '2026-01-01T00:00:00.000Z',
        'text': 'Full body',
      },
    ]);
    await cache.upsertDocuments([
      {
        'id': 'd1',
        'title': 'Note',
        'source_type': 'text',
        'status': 'ready',
        'created_at': '2026-01-01T00:00:00.000Z',
      },
    ]);
    expect((await cache.document('d1'))!['text'], 'Full body');
    await cache.wipe();
    expect(await cache.document('d1'), isNull);
  });
}
