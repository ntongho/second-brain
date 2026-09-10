import 'package:dio/dio.dart';
import 'package:second_brain/core/storage/token_store.dart';
import 'package:second_brain/features/auth/domain/auth_user.dart';

/// Single-flight 401 → refresh → retry-once → wipe (01 §5 / 04 S0).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._store, this._dio);

  final TokenStore _store;
  final Dio _dio;
  Future<void>? _inFlight;

  static bool _isPublic(RequestOptions o) {
    final p = o.path;
    return p.contains('/auth/login') ||
        p.contains('/auth/register') ||
        p.contains('/auth/refresh') ||
        o.extra['skipAuth'] == true;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isPublic(options)) {
      final access = await _store.readAccess();
      if (access != null && access.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || _isPublic(err.requestOptions)) {
      handler.next(err);
      return;
    }
    if (err.requestOptions.extra['_retried'] == true) {
      await _store.wipe();
      handler.next(err);
      return;
    }
    try {
      await _refreshSingleFlight();
      final req = err.requestOptions;
      req.extra['_retried'] = true;
      final access = await _store.readAccess();
      if (access != null) {
        req.headers['Authorization'] = 'Bearer $access';
      }
      final res = await _dio.fetch(req);
      handler.resolve(res);
    } catch (_) {
      await _store.wipe();
      handler.next(err);
    }
  }

  Future<void> _refreshSingleFlight() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _doRefresh();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<void> _doRefresh() async {
    final refresh = await _store.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      throw StateError('no refresh token');
    }
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refresh},
      options: Options(extra: {'skipAuth': true}),
    );
    final data = res.data!;
    await _store.save(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      user: AuthUser.fromJson((data['user'] as Map).cast<String, dynamic>()),
    );
  }
}
