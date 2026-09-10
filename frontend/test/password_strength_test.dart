import 'package:flutter_test/flutter_test.dart';
import 'package:second_brain/features/auth/domain/password_strength.dart';

void main() {
  test('rejects short passwords', () {
    final s = PasswordStrength.of('short');
    expect(s.valid, isFalse);
  });

  test('accepts 10+ chars', () {
    final s = PasswordStrength.of('correct-horse-10');
    expect(s.valid, isTrue);
    expect(s.score, greaterThanOrEqualTo(2));
  });

  test('email validation matches DDL-ish shape', () {
    expect(PasswordStrength.emailValid('ada@example.com'), isTrue);
    expect(PasswordStrength.emailValid('nope'), isFalse);
    expect(PasswordStrength.emailValid('a@b'), isFalse);
  });
}
