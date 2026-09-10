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
    // Listen, don't watch: save() during login used to rebuild this notifier
    // as AsyncLoading, and the login screen treated that as "Could not sign in".
    ref.listen(tokenStoreProvider, (prev, next) {
      Future(() async {
        final user = await ref.read(authRepositoryProvider).restore();
        if (user == null) {
          await ref.read(localCacheProvider).wipe();
          state = const AsyncData(null);
        }
      });
    });
    final user = await ref.read(authRepositoryProvider).restore();
    if (user == null) {
      await ref.read(localCacheProvider).wipe();
    }
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
