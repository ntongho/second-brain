import 'package:flutter/material.dart';
import 'package:second_brain/features/auth/domain/password_strength.dart';

class PasswordMeter extends StatelessWidget {
  const PasswordMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final s = PasswordStrength.of(password);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final on = i < s.score;
            return Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                decoration: BoxDecoration(
                  color: on
                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: s.score >= 3 ? 0.85 : 0.4)
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          password.isEmpty ? 'At least 10 characters' : s.label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
