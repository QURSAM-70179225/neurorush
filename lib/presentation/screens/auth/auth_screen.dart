import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../providers/app_providers.dart';

enum _EmailMode { signIn, register }

/// Sign in / register / guest. With [upgrade] true, links a Google or email
/// account to the current guest so their progress is kept.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.upgrade = false});
  final bool upgrade;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _showEmail = false;
  bool _obscure = true;
  _EmailMode _mode = _EmailMode.signIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.upgrade) _mode = _EmailMode.register;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
      if (widget.upgrade && context.canPop()) context.pop();
    } on AuthFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _google() => _run(
        () => widget.upgrade ? _repo.upgradeGuestWithGoogle() : _repo.signInWithGoogle(),
        success: widget.upgrade ? 'Account linked — your progress is safe!' : null,
      );

  void _guest() => _run(_repo.continueAsGuest);

  void _submitEmail() {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text, pass = _password.text, name = _name.text;
    _run(
      () => switch ((_mode, widget.upgrade)) {
        (_EmailMode.register, true) => _repo.upgradeGuestWithEmail(email, pass, name),
        (_EmailMode.register, false) => _repo.registerWithEmail(email, pass, name),
        (_EmailMode.signIn, _) => _repo.signInWithEmail(email, pass),
      },
      success: widget.upgrade ? 'Account created — your progress is safe!' : null,
    );
  }

  void _resetPassword() {
    final email = _email.text.trim();
    if (!_isEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your email above, then tap "Forgot password".')));
      return;
    }
    _run(() => _repo.sendPasswordReset(email), success: 'Password reset email sent to $email');
  }

  static bool _isEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = _repo.supportsCloudAccounts;
    return Scaffold(
      appBar: widget.upgrade ? AppBar(title: const Text('Save your progress')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.upgrade) ...[
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(
                            gradient: AppPalette.brandGradient, shape: BoxShape.circle),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 56),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('NeuroRush', textAlign: TextAlign.center, style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 6),
                    Text('Sign in to save progress across devices',
                        textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                  ] else
                    Text(
                      'Create an account to keep your XP, scores and streaks, even if you change phones.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  const SizedBox(height: 28),
                  if (!cloud)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Online accounts are unavailable right now. Play as a guest — '
                                'your progress is stored on this device.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (cloud) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _google,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                      label: Text(widget.upgrade ? 'Link Google account' : 'Continue with Google'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => setState(() => _showEmail = !_showEmail),
                      icon: const Icon(Icons.email_rounded),
                      label: Text(_showEmail ? 'Hide email options' : 'Use email'),
                    ),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    child: _showEmail && cloud ? _emailForm(theme) : const SizedBox(width: double.infinity),
                  ),
                  if (!widget.upgrade) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : _guest,
                      child: const Text('Play as guest'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.push('/privacy'), child: const Text('Privacy policy')),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailForm(ThemeData theme) {
    final register = _mode == _EmailMode.register;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.upgrade)
                SegmentedButton<_EmailMode>(
                  segments: const [
                    ButtonSegment(value: _EmailMode.signIn, label: Text('Sign in')),
                    ButtonSegment(value: _EmailMode.register, label: Text('Register')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              const SizedBox(height: 16),
              if (register) ...[
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.nickname],
                  decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.person)),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 3) return 'At least 3 characters';
                    if (t.length > 20) return 'At most 20 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
                validator: (v) => _isEmail(v ?? '') ? null : 'Enter a valid email',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                onFieldSubmitted: (_) => _submitEmail(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if ((v ?? '').length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submitEmail,
                child: Text(register ? 'Create account' : 'Sign in'),
              ),
              if (!register)
                TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Forgot password?')),
            ],
          ),
        ),
      ),
    );
  }
}
