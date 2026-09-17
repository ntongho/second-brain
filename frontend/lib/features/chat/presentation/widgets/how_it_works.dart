import 'package:flutter/material.dart';

Future<void> showHowItWorks(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final muted = Theme.of(ctx).textTheme.bodySmall;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How it works', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              _step(ctx, '1', 'Add to Library', 'Paste a note, upload a PDF, or record a voice memo. That’s the only knowledge it uses.'),
              const SizedBox(height: 12),
              _step(ctx, '2', 'Ask here', 'Type in the box at the bottom. It searches your library, not the open web.'),
              const SizedBox(height: 12),
              _step(ctx, '3', 'Check the citations', 'Answers point at your files. If it isn’t in the library, it says so.'),
              const SizedBox(height: 20),
              Text('Nothing leaves this machine except the AI APIs you already configured.', style: muted),
            ],
          ),
        ),
      );
    },
  );
}

Widget _step(BuildContext context, String n, String title, String body) {
  final on = Theme.of(context).colorScheme.onSurface;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(n, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(body, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}
