import 'package:flutter/material.dart';
import 'package:second_brain/core/theme/tokens.dart';

/// Bars follow live mic levels (0–1). Idle = flat.
class AudioWaveform extends StatelessWidget {
  const AudioWaveform({super.key, this.levels = const [], this.active = false});

  final List<double> levels;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bars = levels.isEmpty ? List<double>.filled(24, 0.12) : levels;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x14F59E0B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SbTokens.audio.withValues(alpha: active ? 0.8 : 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final lv in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  height: 8 + lv.clamp(0, 1) * 52,
                  decoration: BoxDecoration(
                    color: SbTokens.audio.withValues(alpha: active ? 0.95 : 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
