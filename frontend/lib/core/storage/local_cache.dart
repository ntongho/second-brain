import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Write-through mirror of pack 03 §3.3 Isar collections.
///
/// Deviation (flagged): SharedPreferences JSON instead of `isar_community` codegen
/// (not web-safe; needs build_runner). Same collections + logout wipe.
/// Phase 7: `documents` (offline library) + `outbox` (queued asks).
final localCacheProvider = Provider<LocalCache>((ref) => LocalCache());

/// Bumped after outbox enqueue/remove so [SyncQueueNotifier] can refresh counts
/// without a chat ↔ queue import cycle.
final outboxTickProvider = StateProvider<int>((ref) => 0);

class LocalCache {
  LocalCache({Map<String, String>? memory}) : _memory = memory;

  static const _k = 'sb.isar_mirror.v1';

  final Map<String, String>? _memory;
  Map<String, dynamic> _root = _emptyRoot();
  bool _loaded = false;

  static Map<String, dynamic> _emptyRoot() => {
        'threads': <String, dynamic>{},
        'messages': <String, dynamic>{},
        'documents': <String, dynamic>{},
        'outbox': <String, dynamic>{},
      };

  Future<void> _ensure() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = _memory != null ? _memory![_k] : (await SharedPreferences.getInstance()).getString(_k);
      if (raw != null && raw.isNotEmpty) {
        _root = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {
      _root = _emptyRoot();
    }
    _root.putIfAbsent('threads', () => <String, dynamic>{});
    _root.putIfAbsent('messages', () => <String, dynamic>{});
    _root.putIfAbsent('documents', () => <String, dynamic>{});
    _root.putIfAbsent('outbox', () => <String, dynamic>{});
  }

  Future<void> _flush() async {
    final raw = jsonEncode(_root);
    if (_memory != null) {
      _memory![_k] = raw;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k, raw);
  }

  Map<String, dynamic> _map(String key) => Map<String, dynamic>.from(_root[key] as Map? ?? {});

  Future<void> upsertThread({required String remoteId, required String title, DateTime? updatedAt}) async {
    await _ensure();
    final threads = _map('threads');
    threads[remoteId] = {
      'remoteId': remoteId,
      'title': title,
      'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    _root['threads'] = threads;
    await _flush();
  }

  Future<void> replaceMessagesFor(String chatRemoteId, List<Map<String, dynamic>> msgs) async {
    await _ensure();
    final messages = _map('messages');
    messages.removeWhere((_, v) => (v as Map)['chatRemoteId'] == chatRemoteId);
    for (final m in msgs) {
      final id = m['id'] as String?;
      if (id == null || id.isEmpty) continue;
      messages[id] = m;
    }
    _root['messages'] = messages;
    await _flush();
  }

  Future<void> upsertMessageJson(Map<String, dynamic> msg) async {
    await _ensure();
    final messages = _map('messages');
    messages[msg['id'] as String] = msg;
    _root['messages'] = messages;
    await _flush();
  }

  Future<List<Map<String, dynamic>>> messagesFor(String chatRemoteId) async {
    await _ensure();
    final messages = _map('messages');
    final out = <Map<String, dynamic>>[];
    for (final v in messages.values) {
      final m = (v as Map).cast<String, dynamic>();
      if (m['chatRemoteId'] == chatRemoteId) out.add(m);
    }
    out.sort((a, b) => (a['createdAt'] as String? ?? '').compareTo(b['createdAt'] as String? ?? ''));
    return out;
  }

  Future<List<Map<String, dynamic>>> threads() async {
    await _ensure();
    final threads = _map('threads');
    final list = threads.values.map((e) => (e as Map).cast<String, dynamic>()).toList();
    list.sort((a, b) => (b['updatedAt'] as String? ?? '').compareTo(a['updatedAt'] as String? ?? ''));
    return list;
  }

  Future<void> upsertDocuments(List<Map<String, dynamic>> docs) async {
    await _ensure();
    final map = _map('documents');
    for (final incoming in docs) {
      final id = incoming['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final row = Map<String, dynamic>.from(incoming);
      final prev = (map[id] as Map?)?.cast<String, dynamic>();
      final newText = row['text'] as String?;
      if ((newText == null || newText.isEmpty) && prev != null && (prev['text'] as String?)?.isNotEmpty == true) {
        row['text'] = prev['text'];
      }
      map[id] = row;
    }
    _root['documents'] = map;
    await _flush();
  }

  Future<List<Map<String, dynamic>>> documents() async {
    await _ensure();
    final map = _map('documents');
    final list = map.values.map((e) => (e as Map).cast<String, dynamic>()).toList();
    list.sort((a, b) => (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));
    return list;
  }

  Future<Map<String, dynamic>?> document(String id) async {
    await _ensure();
    final row = _map('documents')[id];
    if (row is Map) return row.cast<String, dynamic>();
    return null;
  }

  Future<void> enqueueOutbox(Map<String, dynamic> item) async {
    await _ensure();
    final id = item['id'] as String? ?? item['idempotencyKey'] as String?;
    if (id == null || id.isEmpty) return;
    final box = _map('outbox');
    box[id] = {...item, 'id': id};
    _root['outbox'] = box;
    await _flush();
  }

  Future<List<Map<String, dynamic>>> pendingOutbox() async {
    await _ensure();
    final box = _map('outbox');
    final list = box.values.map((e) => (e as Map).cast<String, dynamic>()).toList();
    list.sort((a, b) => (a['createdAt'] as String? ?? '').compareTo(b['createdAt'] as String? ?? ''));
    return list;
  }

  Future<void> removeOutbox(String id) async {
    await _ensure();
    final box = _map('outbox');
    box.remove(id);
    _root['outbox'] = box;
    await _flush();
  }

  Future<void> wipe() async {
    _root = _emptyRoot();
    _loaded = true;
    await _flush();
  }
}
