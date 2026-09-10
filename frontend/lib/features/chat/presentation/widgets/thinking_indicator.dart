import 'dart:async';

import 'package:flutter/material.dart';
import 'package:second_brain/core/theme/tokens.dart';

/// Bouncing dots + rotating status so a slow Gemini call doesn't look hung.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> with SingleTickerProviderStateMixin {
  static const _labels = [
    'Searching your library…',
    'Reading sources…',
    'Writing an answer…',
  ];

  late final AnimationController _pulse;
  var _i = 0;
  Timer? _rotate;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _rotate = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _labels.length);
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lo = Theme.of(context).textTheme.bodySmall?.color ?? SbTokens.darkTextLo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            _labels[_i],
            key: ValueKey(_i),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: lo),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var d = 0; d < 3; d++)
                  _Dot(active: _dotActive(d), color: SbTokens.primary),
              ],
            );
          },
        ),
      ],
    );
  }

  bool _dotActive(int d) {
    final t = _pulse.value;
    final start = d * 0.22;
    final local = (t - start) % 1.0;
    return local < 0.45;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(right: 6),
      height: active ? 9 : 7,
      width: active ? 9 : 7,
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 1 : 0.35),
        shape: BoxShape.circle,
      ),
    );
  }
}
