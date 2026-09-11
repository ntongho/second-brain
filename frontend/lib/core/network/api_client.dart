import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:second_brain/core/config.dart';
import 'package:second_brain/core/network/auth_interceptor.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/storage/token_store.dart';
import 'package:uuid/uuid.dart';

final tokenStoreProvider = ChangeNotifierProvider<TokenStore>((ref) => TokenStore());

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'X-App-Version': kAppVersion,
      },
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['X-Request-Id'] ??= const Uuid().v4();
        handler.next(options);
      },
    ),
  );
  dio.interceptors.add(AuthInterceptor(ref.read(tokenStoreProvider), dio));
  return dio;
});

Never mapDioError(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['error'] is Map) {
    final retryAfter = int.tryParse(e.response?.headers.value('retry-after') ?? '');
    throw ApiException.fromBody(
      e.response?.statusCode ?? 0,
      data,
      retryAfter: retryAfter,
    );
  }
  throw ApiException(
    statusCode: e.response?.statusCode ?? 0,
    code: 'INTERNAL',
    message: e.message ?? 'Network error',
    retryable: true,
  );
}
