import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/bi_sign_in_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';
import 'bi_sign_in_messages.dart';

enum _AuthFlow { form, emailSent }

class LoginScreen extends ConsumerStatefulWidget {
  final bool useFallback;

  const LoginScreen({super.key, this.useFallback = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _isBiLoading = false;

  /// Why the last BI sign-in failed, shown under the BI button.
  BiSignInFailure? _biFailure;
  _AuthFlow _flow = _AuthFlow.form;
  String _sentEmail = '';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Please enter a valid email address';
    return null;
  }

  Future<void> _handleSendLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await ref
          .read(authStateProvider.notifier)
          .sendMagicLink(_emailController.text.trim());

      if (mounted) {
        setState(() {
          _sentEmail = _emailController.text.trim();
          _flow = _AuthFlow.emailSent;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send link: $e'),
            backgroundColor: BisoPalette.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Available in debug builds only — simulators can't click email links
  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await ref
          .read(authStateProvider.notifier)
          .sendOtp(_emailController.text.trim());

      if (mounted) {
        context.go('/auth/verify-otp', extra: _emailController.text.trim());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: BisoPalette.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Signs in with BI. A cancelled sheet leaves the screen as it was; a
  /// signed-in student goes on even when the student number did not come
  /// through, which the snackbar then explains.
  Future<void> _handleBiSignIn() async {
    setState(() {
      _isBiLoading = true;
      _biFailure = null;
    });

    BiSignInOutcome outcome;
    try {
      outcome = await ref.read(authStateProvider.notifier).signInWithBi();
    } catch (_) {
      outcome = const BiSignInFailed(BiSignInFailure.failed);
    }
    if (!mounted) return;
    setState(() => _isBiLoading = false);

    switch (outcome) {
      case BiSignInCancelled():
        return;
      case BiSignInFailed(:final reason):
        setState(() => _biFailure = reason);
      case BiSignedIn(:final sync):
        final auth = ref.read(authStateProvider);
        if (!auth.isAuthenticated) {
          setState(() => _biFailure = BiSignInFailure.failed);
          return;
        }
        final message = biSyncMessage(AppLocalizations.of(context)!, sync);
        final messenger = ScaffoldMessenger.of(context);
        context.go(auth.needsOnboarding ? '/onboarding' : '/home');
        if (message != null) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    // Not a themed color: it only chooses which brand logo asset to draw.
    final dark = theme.brightness == Brightness.dark;

    return BisoPage(
      largeTitle: false,
      automaticallyImplyLeading: false,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: _flow == _AuthFlow.emailSent
                ? _buildEmailSentView(theme, palette, dark)
                : _buildFormView(theme, palette, dark),
          ),
        ),
      ],
    );
  }

  Widget _buildFormView(ThemeData theme, BisoPalette palette, bool dark) {
    final l10n = AppLocalizations.of(context)!;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 64),

          // Logo + Title
          Column(
            children: [
              Image.asset(
                dark ? 'assets/logo-dark.png' : 'assets/logo.png',
                height: 72,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),
              Text(
                'Welcome to BISO',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: palette.ink,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),

          const SizedBox(height: 52),

          // BI students sign in with BI; everyone else with a login link.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: FilledButton.icon(
              onPressed: _isBiLoading ? null : _handleBiSignIn,
              icon: _isBiLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.person_crop_rectangle),
              label: Text(l10n.biSignInButton),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.biSignInHint,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            textAlign: TextAlign.center,
          ),
          if (_biFailure case final failure?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                biSignInFailureMessage(l10n, failure),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Divider
          Row(
            children: [
              const Expanded(child: Divider()),
              Flexible(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.biSignInDivider,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),

          const SizedBox(height: 24),

          // Email input
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: _validateEmail,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'your@bi.no',
              prefixIcon: Icon(CupertinoIcons.mail),
            ),
            onFieldSubmitted: (_) => _handleSendLink(),
          ),

          const SizedBox(height: 16),

          OutlinedButton(
            onPressed: _isLoading ? null : _handleSendLink,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send me a sign-in link'),
          ),

          // Debug only: OTP fallback for simulator testing
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isLoading ? null : _handleSendOtp,
              child: const Text('[DEV] Use verification code instead'),
            ),
          ],

          const Spacer(),

          Text(
            'BI Student Organisation',
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEmailSentView(ThemeData theme, BisoPalette palette, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 64),

        Center(
          child: Image.asset(
            dark ? 'assets/logo-dark.png' : 'assets/logo.png',
            height: 72,
            fit: BoxFit.contain,
          ),
        ),

        const SizedBox(height: 52),

        Center(
          child: BisoIconTile(
            icon: CupertinoIcons.mail_solid,
            accent: BisoAccent.blue,
            size: 80,
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Check your inbox',
          style: theme.textTheme.headlineMedium?.copyWith(color: palette.ink),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        Text(
          "We sent a sign-in link to\n$_sentEmail\n\nTap the link in the email to continue.",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.muted,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 40),

        OutlinedButton(
          onPressed: _isLoading ? null : _handleSendLink,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Resend link'),
        ),

        const SizedBox(height: 12),

        TextButton(
          onPressed: () => setState(() => _flow = _AuthFlow.form),
          child: const Text('Use a different email'),
        ),

        const Spacer(),

        Text(
          'BI Student Organisation',
          style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
