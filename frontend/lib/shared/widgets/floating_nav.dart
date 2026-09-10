import 'package:flutter/material.dart';

/// Right-side panel. Short slide so it feels instant.
Future<T?> showFloatingNav<T>({
  required BuildContext context,
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 80),
    pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final size = MediaQuery.sizeOf(ctx);
      final width = size.width >= 720 ? 440.0 : size.width * 0.92;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              elevation: 16,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width,
                height: size.height - 24,
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}
