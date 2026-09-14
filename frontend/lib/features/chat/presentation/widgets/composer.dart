import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:second_brain/core/theme/tokens.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.enabled,
    required this.streaming,
    required this.onSend,
    required this.onCancel,
    this.onAdd,
  });

  final bool enabled;
  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;
  final VoidCallback? onAdd;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctl.text.trim();
    if (t.isEmpty || !widget.enabled || widget.streaming) return;
    HapticFeedback.lightImpact();
    widget.onSend(t);
    _ctl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Add to library',
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
            Expanded(
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                enabled: widget.enabled && !widget.streaming,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(color: onSurface, fontSize: 16),
                cursorColor: SbTokens.primary,
                textInputAction: TextInputAction.send,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'Ask anything',
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 48,
              width: 48,
              child: widget.streaming
                  ? IconButton.filledTonal(
                      tooltip: 'Cancel',
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.stop),
                    )
                  : IconButton.filled(
                      tooltip: 'Send',
                      onPressed: widget.enabled && _ctl.text.trim().isNotEmpty ? _submit : null,
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                      icon: Icon(Icons.arrow_upward, color: Theme.of(context).colorScheme.onPrimary, size: 20),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
