import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:second_brain/features/auth/domain/auth_user.dart';

/// Tokens live ONLY here (01 §6 / 03 §3.3). Never SharedPreferences / Isar.
class TokenStore extends ChangeNotifier {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'sb.access_token';
  static const _kRefresh = 'sb.refresh_token';
  static const _kUser = 'sb.user';

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required AuthUser user,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<String?> readAccess() => _storage.read(key: _kAccess);
  Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  Future<AuthUser?> readUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> wipe() async {
    await _storage.deleteAll();
    notifyListeners();
  }
}
