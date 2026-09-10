import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/theme/tokens.dart';

/// 04 IngestFAB speed-dial. PDF/voice land in later phases.
class IngestFab extends StatelessWidget {
  const IngestFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SbTokens.radiusFab)),
      onPressed: () async {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.notes_outlined),
                  title: const Text('Paste text'),
                  onTap: () => Navigator.pop(ctx, 'text'),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Upload file'),
                  subtitle: const Text('PDF, Markdown, .txt'),
                  onTap: () => Navigator.pop(ctx, 'pdf'),
                ),
                ListTile(
                  leading: const Icon(Icons.mic_none),
                  title: const Text('Record audio'),
                  onTap: () => Navigator.pop(ctx, 'voice'),
                ),
              ],
            ),
          ),
        );
        if (!context.mounted) return;
        if (choice == 'text') context.push('/ingest/text');
        if (choice == 'pdf') context.push('/ingest/pdf');
        if (choice == 'voice') context.push('/ingest/voice');
      },
      child: const Icon(Icons.add),
    );
  }
}
