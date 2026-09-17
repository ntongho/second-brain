import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:second_brain/core/network/api_client.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/storage/local_cache.dart';
import 'package:second_brain/features/auth/data/auth_repository.dart';
import 'package:second_brain/features/auth/domain/auth_user.dart';

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    var alive = true;
    ref.onDispose(() => alive = false);
    // Listen, don't watch: save() during login used to rebuild this notifier
    // as AsyncLoading, and the login screen treated that as "Could not sign in".
    ref.listen(tokenStoreProvider, (prev, next) {
      Future(() async {
        final user = await ref.read(authRepositoryProvider).restore(refresh: false);
        if (!alive) return;
        if (user == null) {
          await ref.read(localCacheProvider).wipe();
          state = const AsyncData(null);
        }
      });
    });
    final user = await ref.read(authRepositoryProvider).restore(refresh: false);
    if (user == null) {
      await ref.read(localCacheProvider).wipe();
      return null;
    }
    // Do not POST /auth/refresh here. Chats also 401 → refresh; two refreshes
    // with the same token revoke the whole chain (refresh_reuse_revoked_chain).
    return user;
  }

  bool get isAuthenticated => state.asData?.value != null;

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).login(email: email, password: password),
    );
  }

  Future<void> register(String email, String password, {String? displayName}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).register(
            email: email,
            password: password,
            displayName: displayName,
          ),
    );
  }

  Future<void> loginGoogle({String? idToken, String? accessToken}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).loginGoogle(idToken: idToken, accessToken: accessToken),
    );
  }

  Future<({bool emailed, String? devCode})> forgotPassword(String email) {
    return ref.read(authRepositoryProvider).forgotPassword(email: email);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).resetPassword(
            email: email,
            code: code,
            password: password,
          ),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    await ref.read(localCacheProvider).wipe();
    state = const AsyncData(null);
  }

  ApiException? get lastApiError {
    final err = state.error;
    return err is ApiException ? err : null;
  }
}
