import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';

/// Returns true if [e] was a duplicate and we handled it.
Future<bool> showIfDuplicate(BuildContext context, ApiException e) async {
  if (e.statusCode != 409 && e.code != 'CONFLICT') return false;
  final id = e.details['document_id'] as String?;
  final title = (e.details['title'] as String?) ?? 'that file';
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Already in your library'),
      content: Text('“$title” is already saved. Open it instead of uploading again?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Dismiss')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
      ],
    ),
  );
  if (open == true && id != null && context.mounted) {
    context.go('/doc/$id');
  }
  return true;
}
