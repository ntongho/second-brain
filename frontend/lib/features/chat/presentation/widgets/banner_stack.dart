import 'package:flutter/material.dart';
import 'package:second_brain/core/theme/tokens.dart';

/// 04 BannerStack: red offline > amber degraded > indigo sync.
class BannerStack extends StatelessWidget {
  const BannerStack({
    super.key,
    required this.offline,
    required this.degraded,
    this.syncLabel,
    this.queued = 0,
  });

  final bool offline;
  final bool degraded;
  final String? syncLabel;
  final int queued;

  @override
  Widget build(BuildContext context) {
    if (offline) {
      return _Banner(
        color: SbTokens.danger,
        text: queued > 0
            ? 'Offline — $queued queued. Library readable, AI paused.'
            : 'Offline — library readable, AI paused.',
      );
    }
    if (degraded) {
      return const _Banner(
        color: SbTokens.audio,
        text: 'AI unavailable — showing keyword matches',
      );
    }
    if (syncLabel != null && syncLabel!.isNotEmpty) {
      return _Banner(color: SbTokens.primary, text: syncLabel!);
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
