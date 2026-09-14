import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/chat/domain/chat_message.dart';
import 'package:second_brain/features/chat/presentation/widgets/citation_chip.dart';
import 'package:second_brain/features/chat/presentation/widgets/thinking_indicator.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.devMode = false,
    this.onRegenerate,
    this.onRetry,
    this.onCancel,
  });

  final ChatMessage message;
  final bool devMode;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(SbTokens.radiusBubble),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(message.content, style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    final degraded = message.degraded;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: const BoxDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (degraded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '⚠ Keyword matches (AI unavailable)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.audio),
                ),
              ),
            if (message.queued)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Queued — waiting for a connection.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.audio),
                ),
              ),
            if (message.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Couldn’t finish that answer.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.danger),
                ),
              ),
            if (message.streaming && message.content.isEmpty)
              const ThinkingIndicator()
            else
              SelectableText(
                '${message.content}${message.streaming ? '▍' : ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (message.citations.isNotEmpty)
              Wrap(
                children: [
                  for (var i = 0; i < message.citations.length; i++)
                    CitationChip(index: i + 1, citation: message.citations[i]),
                ],
              ),
            if (!message.streaming || message.content.isNotEmpty) const SizedBox(height: 8),
            if (message.streaming && message.content.isEmpty)
              TextButton(onPressed: onCancel, child: const Text('Cancel'))
            else
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: message.content.isEmpty ? null : () => _copy(context, message.content),
                    child: const Text('Copy'),
                  ),
                  if (message.streaming)
                    TextButton(onPressed: onCancel, child: const Text('Cancel'))
                  else if (message.failed || message.queued)
                    TextButton(onPressed: onRetry, child: const Text('Retry'))
                  else
                    TextButton(onPressed: onRegenerate, child: const Text('↻')),
                  if (message.citations.isNotEmpty)
                    TextButton(
                      onPressed: () => _viewSources(context),
                      child: Text('View sources(${message.citations.length})'),
                    ),
                ],
              ),
            if (devMode)
              Text(
                [
                  if (message.mode != null) 'mode=${message.mode}',
                  'degraded=${message.degraded}',
                  if (message.latencyMs != null) '${message.latencyMs}ms',
                  if (message.promptTokens != null) 'in=${message.promptTokens}',
                  if (message.completionTokens != null) 'out=${message.completionTokens}',
                  if (message.citations.isNotEmpty)
                    'retrieval=${message.citations.map((c) => c.retrieval).toSet().join(",")}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _viewSources(BuildContext context) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            itemCount: message.citations.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final c = message.citations[i];
              final page = c.page == null ? '' : ' · p.${c.page}';
              return ListTile(
                title: Text('[${i + 1}] ${c.title}$page'),
                subtitle: Text(c.snippet, maxLines: 3, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  Navigator.pop(ctx);
                  await openCitationPreview(context, index: i + 1, citation: c);
                },
              );
            },
          ),
        );
      },
    );
  }
}
