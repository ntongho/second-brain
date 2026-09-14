import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/auth/application/auth_controller.dart';
import 'package:second_brain/features/settings/data/admin_repository.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  List<AdminUserRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(adminRepositoryProvider).listUsers();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _act(AdminUserRow row, String action) async {
    final repo = ref.read(adminRepositoryProvider);
    try {
      switch (action) {
        case 'unlock':
          await repo.unlock(row.id);
          break;
        case 'revoke':
          await repo.revokeSessions(row.id);
          break;
        case 'reset':
          await repo.sendReset(row.id);
          break;
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete this user?'),
              content: Text(
                'This permanently deletes ${row.email} and their chats, notes, and files on this server.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
              ],
            ),
          );
          if (ok != true) return;
          await repo.deleteUser(row.id);
          break;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_doneLabel(action, row.email))));
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _doneLabel(String action, String email) {
    return switch (action) {
      'unlock' => 'Unlocked $email',
      'revoke' => 'Signed $email out of all devices',
      'reset' => 'Reset email sent to $email',
      'delete' => 'Deleted $email',
      _ => 'Done',
    };
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [IconButton(tooltip: 'Reload', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = _rows[i];
                    final mine = me?.id == row.id;
                    return ListTile(
                      title: Text(row.email, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        [
                          if (row.displayName.isNotEmpty) row.displayName,
                          if (row.isAdmin) 'operator',
                          if (row.isLocked) 'locked',
                          if (row.failedAttempts > 0) '${row.failedAttempts} failed sign-ins',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: row.isLocked ? SbTokens.danger : Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      trailing: mine
                          ? const Text('You', style: TextStyle(fontSize: 12))
                          : PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz),
                              onSelected: (v) => _act(row, v),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'unlock', child: Text('Unlock')),
                                const PopupMenuItem(value: 'revoke', child: Text('Sign out all devices')),
                                const PopupMenuItem(value: 'reset', child: Text('Send reset email')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete user')),
                              ],
                            ),
                    );
                  },
                ),
    );
  }
}
