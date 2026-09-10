/// Client-side password rules (F0): min 10, max 72. Strength meter is UX-only.
class PasswordStrength {
  const PasswordStrength({
    required this.score,
    required this.label,
    required this.valid,
  });

  /// 0–4
  final int score;
  final String label;
  final bool valid;

  static PasswordStrength of(String password) {
    if (password.length > 72) {
      return const PasswordStrength(score: 0, label: 'Too long', valid: false);
    }
    var score = 0;
    if (password.length >= 10) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    // Cap display at 4 bars; length is the validity gate.
    final bars = score.clamp(0, 4);
    final valid = password.length >= 10 && password.length <= 72;
    final label = switch (bars) {
      0 || 1 => 'Weak',
      2 => 'Fair',
      3 => 'Good',
      _ => 'Strong',
    };
    return PasswordStrength(score: bars, label: label, valid: valid);
  }

  static bool emailValid(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  }
}
