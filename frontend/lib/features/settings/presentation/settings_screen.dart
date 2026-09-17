import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/config.dart';
import 'package:second_brain/core/network/api_client.dart';
import 'package:second_brain/core/theme/appearance_sheet.dart';
import 'package:second_brain/core/theme/theme_controller.dart';
import 'package:second_brain/features/auth/application/auth_controller.dart';
import 'package:second_brain/features/chat/presentation/widgets/how_it_works.dart';

final _readyProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final res = await ref.watch(dioProvider).get<Map<String, dynamic>>('/readyz');
    return res.data ?? {};
  } catch (_) {
    return {};
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.asPanel = false});

  final bool asPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).asData?.value;
    final ready = ref.watch(_readyProvider).asData?.value ?? {};
    final backup = (ready['backup'] as Map?)?['last_ok'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: asPanel
            ? IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Account'),
            subtitle: Text(user?.email ?? ''),
          ),
          ListTile(
            title: const Text('API'),
            subtitle: const Text(kApiBaseUrl),
          ),
          ListTile(
            title: const Text('Version'),
            subtitle: const Text(kAppVersion),
          ),
          ListTile(
            title: const Text('Last backup'),
            subtitle: Text(backup == null || backup.isEmpty ? 'None yet (daily 03:15 UTC)' : backup),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(switch (ref.watch(themeModeProvider)) {
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
              ThemeMode.system => 'Match device',
            }),
            onTap: () => showAppearanceSheet(context),
          ),
          ListTile(
            title: const Text('How it works'),
            subtitle: const Text('Library → ask → citations'),
            onTap: () => showHowItWorks(context),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text('This wipes tokens and local chat cache on this device.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              }
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
