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
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
              webOptions: WebOptions(),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'sb.access_token';
  static const _kRefresh = 'sb.refresh_token';
  static const _kUser = 'sb.user';

  String? _access;
  String? _refresh;
  AuthUser? _user;
  var _hydrated = false;

  Future<void> _hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      _access = await _storage.read(key: _kAccess);
      _refresh = await _storage.read(key: _kRefresh);
      final raw = await _storage.read(key: _kUser);
      if (raw != null && raw.isNotEmpty) {
        _user = AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required AuthUser user,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
    _user = user;
    _hydrated = true;
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<String?> readAccess() async {
    await _hydrate();
    return _access;
  }

  Future<String?> readRefresh() async {
    await _hydrate();
    return _refresh;
  }

  Future<AuthUser?> readUser() async {
    await _hydrate();
    return _user;
  }

  Future<void> wipe() async {
    _access = null;
    _refresh = null;
    _user = null;
    _hydrated = true;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
    notifyListeners();
  }
}
