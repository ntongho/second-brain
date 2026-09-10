import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/auth/application/auth_controller.dart';
import 'package:second_brain/features/auth/domain/password_strength.dart';
import 'package:second_brain/features/auth/presentation/widgets/auth_field.dart';
import 'package:second_brain/features/auth/presentation/widgets/password_meter.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;
  String? _formError;
  DateTime? _lockedUntil;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _clientValid {
    final emailOk = PasswordStrength.emailValid(_email.text);
    final pwOk = PasswordStrength.of(_password.text).valid;
    return emailOk && pwOk;
  }

  bool get _isLocked {
    final until = _lockedUntil;
    if (until == null) return false;
    return until.isAfter(DateTime.now());
  }

  String? get _countdown {
    if (!_isLocked) return null;
    final left = _lockedUntil!.difference(DateTime.now());
    final m = left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'Try again in ${left.inHours > 0 ? '${left.inHours}:' : ''}$m:$s';
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isLocked) {
        _tick?.cancel();
        _lockedUntil = null;
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = PasswordStrength.emailValid(_email.text) ? null : 'Enter a valid email';
      _passwordError =
          PasswordStrength.of(_password.text).valid ? null : 'Password must be 10–72 characters';
      _formError = null;
    });
    if (!_clientValid || _isLocked) return;

    final notifier = ref.read(authProvider.notifier);
    if (_register) {
      await notifier.register(_email.text, _password.text, displayName: _name.text);
      final err = ref.read(authProvider).error;
      // Existing email → sign in with the same password (gate user, etc.).
      if (err is ApiException && err.code == 'CONFLICT') {
        await notifier.login(_email.text, _password.text);
      }
    } else {
      await notifier.login(_email.text, _password.text);
    }
    if (!mounted) return;
    final snap = ref.read(authProvider);
    // Loading/refresh after a good login is not a failure — router will leave /login.
    if (snap.isLoading || snap.isRefreshing) return;
    if (snap.hasError || snap.asData?.value == null) {
      final err = snap.error;
      setState(() {
        if (err is ApiException) {
          if (err.isLockout) {
            _lockedUntil = err.lockedUntil ?? DateTime.now().add(Duration(seconds: err.retryAfter ?? 900));
            _formError = _countdown;
            _startTick();
          } else if (err.isAuth) {
            _formError = 'Incorrect email or password';
          } else if (err.code == 'RATE_LIMITED') {
            _formError = 'Too many tries. Wait a minute and tap Sign in.';
          } else if (err.code == 'CONFLICT') {
            _register = false;
            _formError = 'That email already has an account. Tap Sign in.';
          } else {
            _formError = err.message;
          }
        } else if (err != null) {
          _formError = err.toString();
        } else {
          _formError = 'Could not sign in';
        }
      });
      return;
    }
    final dest = widget.from;
    if (dest != null && dest.isNotEmpty && dest != '/login') {
      context.go(dest);
    } else {
      context.go('/chat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final busy = auth.isLoading;
    final locked = _isLocked;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Text('Second Brain', style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 8),
                    Text(
                      _register ? 'Create an account' : 'Sign in to your library',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 32),
                    AuthField(
                      controller: _email,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      errorText: _emailError,
                      enabled: !busy && !locked,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    AuthField(
                      controller: _password,
                      label: 'Password',
                      obscure: _obscure,
                      onToggleObscure: () => setState(() => _obscure = !_obscure),
                      autofillHints: _register
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      errorText: _passwordError,
                      enabled: !busy && !locked,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      PasswordMeter(password: _password.text),
                      const SizedBox(height: 12),
                      AuthField(
                        controller: _name,
                        label: 'Display name (optional)',
                        enabled: !busy && !locked,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                    if (_formError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        locked ? (_countdown ?? _formError!) : _formError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SbTokens.danger),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy || locked || !_clientValid ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_register ? 'Create account' : 'Continue'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: busy || locked
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _formError = null;
                              }),
                      child: Text(_register ? 'Have an account? Sign in' : 'New here? Create account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
