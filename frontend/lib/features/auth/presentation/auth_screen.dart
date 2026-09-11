import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:second_brain/core/config.dart';
import 'package:second_brain/core/network/error_envelope.dart';
import 'package:second_brain/core/theme/tokens.dart';
import 'package:second_brain/features/auth/application/auth_controller.dart';
import 'package:second_brain/features/auth/data/google_sign_in.dart';
import 'package:second_brain/features/auth/domain/password_strength.dart';
import 'package:second_brain/features/auth/presentation/widgets/auth_field.dart';
import 'package:second_brain/features/auth/presentation/widgets/password_meter.dart';

enum _AuthMode { login, register, forgot, reset }

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
  final _code = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;
  String? _codeError;
  String? _formError;
  DateTime? _lockedUntil;
  Timer? _tick;
  bool _googleBusy = false;

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _clientValid {
    final emailOk = PasswordStrength.emailValid(_email.text);
    if (_mode == _AuthMode.forgot) return emailOk;
    if (_mode == _AuthMode.reset) {
      return emailOk && _code.text.trim().length == 6 && PasswordStrength.of(_password.text).valid;
    }
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

  void _goAfterAuth() {
    final dest = widget.from;
    if (dest != null && dest.isNotEmpty && dest != '/login') {
      context.go(dest);
    } else {
      context.go('/chat');
    }
  }

  String _googleError(Object e) {
    if (e is ApiException) return e.message;
    final s = e.toString();
    if (s.contains('popup') || s.contains('closed')) {
      return 'Google popup was blocked or closed. Allow popups for localhost, then try again.';
    }
    if (s.contains('idpiframe') || s.contains('origin') || s.contains('redirect_uri')) {
      return 'Google blocked this Chrome origin. In Google Cloud → Web client → Authorized JavaScript origins, add the exact URL in the address bar (http://localhost:PORT), wait a minute, restart Flutter.';
    }
    if (s.contains('People API') || s.contains('403')) {
      return 'Enable the People API / Google Identity in this Google Cloud project.';
    }
    final cut = s.length > 220 ? '${s.substring(0, 220)}…' : s;
    return 'Google sign-in failed. $cut';
  }

  Future<void> _finishAuth({bool google = false}) async {
    if (!mounted) return;
    final snap = ref.read(authProvider);
    if (snap.isLoading || snap.isRefreshing) return;
    if (snap.hasError || snap.asData?.value == null) {
      final err = snap.error;
      setState(() {
        if (err is ApiException) {
          if (err.isLockout) {
            _lockedUntil = err.lockedUntil ?? DateTime.now().add(Duration(seconds: err.retryAfter ?? 900));
            _formError = _countdown;
            _startTick();
          } else if (google) {
            _formError = err.message;
          } else if (err.isAuth) {
            _formError = _mode == _AuthMode.reset ? 'Invalid or expired code' : 'Incorrect email or password';
          } else if (err.code == 'RATE_LIMITED') {
            _formError = 'Too many tries. Wait a minute and tap Sign in.';
          } else if (err.code == 'CONFLICT') {
            _mode = _AuthMode.login;
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
    _goAfterAuth();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = PasswordStrength.emailValid(_email.text) ? null : 'Enter a valid email';
      _passwordError = (_mode == _AuthMode.forgot || PasswordStrength.of(_password.text).valid)
          ? null
          : 'Password must be 10–72 characters';
      _codeError = (_mode != _AuthMode.reset || _code.text.trim().length == 6) ? null : 'Enter the 6-digit code';
      _formError = null;
    });
    if (!_clientValid || _isLocked) return;

    final notifier = ref.read(authProvider.notifier);
    if (_mode == _AuthMode.forgot) {
      try {
        final result = await notifier.forgotPassword(_email.text);
        if (!mounted) return;
        setState(() {
          _mode = _AuthMode.reset;
          if (result.devCode != null) {
            _code.text = result.devCode!;
            _formError = 'Reset code: ${result.devCode} — set a new password.';
          } else if (result.emailed) {
            _formError = 'Check your email for a 6-digit code.';
          } else {
            _formError = 'If that email is registered, enter the code we sent.';
          }
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _formError = e.message);
      }
      return;
    }

    if (_mode == _AuthMode.reset) {
      await notifier.resetPassword(email: _email.text, code: _code.text, password: _password.text);
      await _finishAuth();
      return;
    }

    if (_mode == _AuthMode.register) {
      await notifier.register(_email.text, _password.text, displayName: _name.text);
      final err = ref.read(authProvider).error;
      if (err is ApiException && err.code == 'CONFLICT') {
        await notifier.login(_email.text, _password.text);
      }
    } else {
      await notifier.login(_email.text, _password.text);
    }
    await _finishAuth();
  }

  Future<void> _google() async {
    if (_isLocked) return;
    if (kGoogleClientId.isEmpty) {
      setState(() {
        _formError =
            'Google sign-in needs a Web client ID. Add GOOGLE_CLIENT_ID to the API .env and run Flutter with --dart-define=GOOGLE_CLIENT_ID=…apps.googleusercontent.com';
      });
      return;
    }
    setState(() {
      _googleBusy = true;
      _formError = null;
    });
    try {
      final tokens = await requestGoogleTokens();
      if (!mounted) return;
      if (tokens == null) {
        setState(() => _googleBusy = false);
        return;
      }
      await ref.read(authProvider.notifier).loginGoogle(
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
          );
      await _finishAuth(google: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = _googleError(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.register:
        return 'Create an account';
      case _AuthMode.forgot:
        return 'Reset your password';
      case _AuthMode.reset:
        return 'Enter the code';
      case _AuthMode.login:
        return 'Sign in to your library';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final busy = auth.isLoading || _googleBusy;
    final locked = _isLocked;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: ListView(
                  children: [
                    const SizedBox(height: 32),
                    Text('Second Brain', style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 8),
                    Text(_title, style: Theme.of(context).textTheme.bodySmall),
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
                    if (_mode == _AuthMode.reset) ...[
                      const SizedBox(height: 12),
                      AuthField(
                        controller: _code,
                        label: '6-digit code',
                        keyboardType: TextInputType.number,
                        errorText: _codeError,
                        enabled: !busy && !locked,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    if (_mode != _AuthMode.forgot) ...[
                      const SizedBox(height: 12),
                      AuthField(
                        controller: _password,
                        label: _mode == _AuthMode.reset ? 'New password' : 'Password',
                        obscure: _obscure,
                        onToggleObscure: () => setState(() => _obscure = !_obscure),
                        autofillHints: _mode == _AuthMode.login
                            ? const [AutofillHints.password]
                            : const [AutofillHints.newPassword],
                        errorText: _passwordError,
                        enabled: !busy && !locked,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    if (_mode == _AuthMode.register || _mode == _AuthMode.reset) ...[
                      const SizedBox(height: 12),
                      PasswordMeter(password: _password.text),
                    ],
                    if (_mode == _AuthMode.register) ...[
                      const SizedBox(height: 12),
                      AuthField(
                        controller: _name,
                        label: 'Display name (optional)',
                        enabled: !busy && !locked,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                    if (_mode == _AuthMode.login)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: busy || locked
                              ? null
                              : () => setState(() {
                                    _mode = _AuthMode.forgot;
                                    _formError = null;
                                  }),
                          child: const Text('Forgot password?'),
                        ),
                      ),
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
                          : Text(switch (_mode) {
                              _AuthMode.register => 'Create account',
                              _AuthMode.forgot => 'Send reset code',
                              _AuthMode.reset => 'Set new password',
                              _AuthMode.login => 'Continue',
                            }),
                    ),
                    if (_mode == _AuthMode.login || _mode == _AuthMode.register) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or', style: Theme.of(context).textTheme.bodySmall),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: busy || locked ? null : _google,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                        child: const Text('Continue with Google'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: busy || locked
                          ? null
                          : () => setState(() {
                                _mode = _mode == _AuthMode.login ? _AuthMode.register : _AuthMode.login;
                                _formError = null;
                              }),
                      child: Text(
                        _mode == _AuthMode.register || _mode == _AuthMode.forgot || _mode == _AuthMode.reset
                            ? 'Have an account? Sign in'
                            : 'New here? Create account',
                      ),
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
