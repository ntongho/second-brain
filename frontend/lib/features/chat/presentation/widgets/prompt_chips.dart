import 'package:flutter/material.dart';

const kOnboardingPrompts = [
  'What is the rule of 72?',
  'Summarize my Japan trip',
  'What did we decide about the Q3 budget?',
];

List<String> followUpsFor(String query) {
  var cleaned = query.trim().replaceAll(RegExp(r'[?!.]+$'), '');
  if (cleaned.isEmpty) return const [];
  if (cleaned.length > 42) cleaned = '${cleaned.substring(0, 42).trim()}…';
  return [
    'What else is in my library about “$cleaned”?',
    'Give me a shorter summary of that',
    'Any dates or numbers I should remember?',
  ];
}

class PromptChips extends StatelessWidget {
  const PromptChips({super.key, required this.onPick, this.prompts = kOnboardingPrompts});

  final ValueChanged<String> onPick;
  final List<String> prompts;

  @override
  Widget build(BuildContext context) {
    if (prompts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in prompts)
            ActionChip(
              label: Text(p),
              onPressed: () => onPick(p),
            ),
        ],
      ),
    );
  }
}
