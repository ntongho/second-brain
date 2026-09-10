import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/features/auth/application/auth_controller.dart';
import 'package:second_brain/features/auth/presentation/auth_screen.dart';
import 'package:second_brain/features/chat/presentation/chat_screen.dart';
import 'package:second_brain/features/chat/presentation/chats_screen.dart';
import 'package:second_brain/features/ingestion/presentation/add_text_screen.dart';
import 'package:second_brain/features/ingestion/presentation/record_audio_screen.dart';
import 'package:second_brain/features/ingestion/presentation/upload_pdf_screen.dart';
import 'package:second_brain/features/library/presentation/library_screen.dart';
import 'package:second_brain/features/settings/presentation/settings_screen.dart';
import 'package:second_brain/features/viewer/presentation/document_viewer_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final loggingIn = loc == '/login';
      final splashing = loc == '/splash';

      // Stay on /login while a sign-in request is in flight (don't flash splash).
      if ((auth.isLoading || auth.isRefreshing) && !loggingIn) {
        return splashing ? null : '/splash';
      }

      final loggedIn = auth.asData?.value != null;
      if (!loggedIn && !loggingIn) {
        final from = state.uri.toString();
        if (splashing) return '/login';
        return '/login?from=${Uri.encodeComponent(from)}';
      }
      if (loggedIn && (loggingIn || splashing)) {
        final dest = state.uri.queryParameters['from'];
        if (dest != null && dest.isNotEmpty && dest != '/login' && dest != '/splash') {
          return dest;
        }
        return '/chat';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const _Splash()),
      GoRoute(
        path: '/login',
        builder: (c, s) => AuthScreen(from: s.uri.queryParameters['from']),
      ),
      GoRoute(path: '/chat', builder: (c, s) => const ChatScreen()),
      GoRoute(
        path: '/chat/:chatId',
        builder: (c, s) => ChatScreen(chatId: s.pathParameters['chatId']),
      ),
      GoRoute(path: '/chats', builder: (c, s) => const ChatsScreen()),
      GoRoute(path: '/library', builder: (c, s) => const LibraryScreen()),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(
        path: '/ingest/text',
        builder: (c, s) => AddTextScreen(docId: s.uri.queryParameters['id']),
      ),
      GoRoute(path: '/ingest/pdf', builder: (c, s) => const UploadPdfScreen()),
      GoRoute(path: '/ingest/voice', builder: (c, s) => const RecordAudioScreen()),
      GoRoute(
        path: '/doc/:id',
        builder: (c, s) => DocumentViewerScreen(
          docId: s.pathParameters['id']!,
          highlightChunkId: s.uri.queryParameters['highlight'],
        ),
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _sub = _ref.listen(authProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<dynamic>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
