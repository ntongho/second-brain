import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/chat/domain/citation.dart';

class CitationChip extends StatelessWidget {
  const CitationChip({super.key, required this.index, required this.citation});

  final int index;
  final Citation citation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 6),
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: SbTokens.citation.withValues(alpha: 0.16),
        side: BorderSide(color: SbTokens.citation.withValues(alpha: 0.5)),
        label: Text(
          '[$index] ${citation.title}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.citation),
        ),
        onPressed: () => openCitationPreview(context, index: index, citation: citation),
      ),
    );
  }
}

Future<void> openCitationPreview(
  BuildContext context, {
  required int index,
  required Citation citation,
}) async {
  HapticFeedback.selectionClick();
  final router = GoRouter.of(context);
  final snippet = citation.snippet.length > 400 ? citation.snippet.substring(0, 400) : citation.snippet;
  final pageBit = citation.page == null ? '' : ' · p.${citation.page}';
  final action = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: Text('[$index] ${citation.title}$pageBit'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: SelectableText(snippet)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: snippet));
              Navigator.pop(ctx, 'copy');
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text('Close')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'open'),
            child: const Text('Open in document'),
          ),
        ],
      );
    },
  );
  if (action == 'copy' && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }
  if (action == 'open' && context.mounted) {
    router.push('/doc/${citation.documentId}?highlight=${Uri.encodeComponent(citation.chunkId)}');
  }
}
