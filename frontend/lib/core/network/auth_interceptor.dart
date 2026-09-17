import 'package:dio/dio.dart';
import 'package:second_brain/core/storage/token_store.dart';
import 'package:second_brain/features/auth/domain/auth_user.dart';

/// 401 → one shared refresh → retry once → wipe and send the caller the error.
/// Not a [QueuedInterceptor]: awaiting inside that class deadlocks Dio (logout/chats hang).
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store, this._dio);

  final TokenStore _store;
  final Dio _dio;
  Future<void>? _inFlight;

  static bool _isPublic(RequestOptions o) {
    final p = o.path;
    return p.contains('/auth/login') ||
        p.contains('/auth/register') ||
        p.contains('/auth/refresh') ||
        p.contains('/auth/logout') ||
        p.contains('/auth/forgot-password') ||
        p.contains('/auth/reset-password') ||
        p.contains('/auth/google') ||
        o.extra['skipAuth'] == true;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      if (!_isPublic(options)) {
        final access = await _store.readAccess();
        if (access != null && access.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $access';
        }
      }
      handler.next(options);
    } catch (e, st) {
      handler.reject(DioException(requestOptions: options, error: e, stackTrace: st));
    }
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
      if (access != null && access.isNotEmpty) {
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
      options: Options(
        extra: {'skipAuth': true},
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final data = res.data!;
    await _store.save(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      user: AuthUser.fromJson((data['user'] as Map).cast<String, dynamic>()),
    );
  }
}
