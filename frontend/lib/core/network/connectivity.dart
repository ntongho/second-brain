import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` = has a network path. Web: Chrome offline mode reports `none`.
final connectivityProvider = NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

class ConnectivityNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  bool build() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen(_apply);
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_prime);
    return true;
  }

  Future<void> _prime() async {
    try {
      _apply(await Connectivity().checkConnectivity());
    } catch (_) {}
  }

  /// Used by chat + library to treat transport failures as offline.
  static bool isOfflineDio(DioException e) {
    if (e.response != null) return false;
    return e.type != DioExceptionType.badResponse && e.type != DioExceptionType.cancel;
  }

  void _apply(List<ConnectivityResult> results) {
    // Ignore empty snapshots (web sometimes emits [] before the first real value).
    if (results.isEmpty) return;
    final online = results.any((r) => r != ConnectivityResult.none);
    if (state != online) state = online;
  }
}
