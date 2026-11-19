import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../nav.dart';
import '../providers.dart';
import 'account_data.dart';
import 'account_screen.dart' show openedAtProvider, pendingEmailProvider;

/// Log in or sign up, as on Bayut, kept simple: the logo, a title, Google,
/// then "or" and email, by a one-time link (no password needed) or with a
/// password set in Edit Profile; one line switches to creating an account.
/// It opens over the page from every Log in button: a window on computers,
/// a sheet from the bottom on phones. Closes itself once signed in.
Future<void> showSignIn(BuildContext context, {bool join = false}) {
  final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: const Key('sign-in-dialog'),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SignInPanel(join: join, closable: true, onSignedIn: () => Navigator.of(context).pop()),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(context.brand.radiusMd * 2))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SignInPanel(key: const Key('sign-in-sheet'), join: join, closable: true, onSignedIn: () => Navigator.of(context).pop()),
    ),
  );
}

enum _Method { link, password }

class SignInPanel extends ConsumerStatefulWidget {
  const SignInPanel({super.key, this.join = false, this.closable = false, this.onSignedIn, this.emailFirst = false});

  /// Opens on "Create an account" instead of "Log in".
  final bool join;

  /// A close button at the top right (in a window or a sheet).
  final bool closable;

  /// Called once the customer is signed in.
  final VoidCallback? onSignedIn;

  /// Opens with the emailed link's box already shown (the Account page).
  final bool emailFirst;

  @override
  ConsumerState<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends ConsumerState<SignInPanel> {
  late bool _join = widget.join;
  late _Method? _method = widget.emailFirst ? _Method.link : null;
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _status, _error;
  bool _busy = false;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// The provider's reason, small, for reports from phones.
  static String _code(Object e) => e is SignInFailure ? ' (${e.code})' : '';

  Future<void> _run(Future<void> Function() job, String failed) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await job();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$failed${_code(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _run(() => ref.read(customerAccountProvider).signInWithGoogle(), 'Google sign-in is not available here yet. Use your email.');

  Future<void> _sendLink() async {
    final email = _email.text.trim();
    if (!_emailShape.hasMatch(email)) {
      setState(() => _error = 'Enter your email address.');
      return;
    }
    await _run(() async {
      // The link opens the web app's Account page (on a phone, the browser).
      final here = ref.read(openedAtProvider);
      final back = here.isScheme('http') || here.isScheme('https')
          ? here.replace(path: '/account', query: '')
          : Uri.https(ref.read(tenantProvider).appDomain, '/account');
      await ref.read(pendingEmailProvider).write(email);
      await ref.read(customerAccountProvider).sendSignInLink(email, back);
      if (mounted) setState(() => _status = 'Check $email for a sign-in link. Open it on this phone or computer.');
    }, 'We could not send the link just now. Please try again.');
  }

  Future<void> _withPassword() async {
    final email = _email.text.trim();
    if (!_emailShape.hasMatch(email) || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email address and password.');
      return;
    }
    await _run(() async {
      await ref.read(customerAccountProvider).signInWithPassword(email, _password.text);
      _password.clear();
    }, 'That email and password do not match. Try again, or use a one-time link.');
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!_emailShape.hasMatch(email)) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    await _run(() async {
      await ref.read(customerAccountProvider).sendPasswordReset(email);
      if (mounted) setState(() => _status = 'Check $email for a link to choose a new password.');
    }, 'We could not send that just now. Please try again.');
  }

  /// A page of the share site as a link inside the disclaimer: bold, underlined, in the brand colour.
  InlineSpan _link(String label, String slug, Key key) {
    final scheme = Theme.of(context).colorScheme;
    final tenant = ref.read(tenantProvider);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: InkWell(
        key: key,
        onTap: () => ref.read(urlOpenerProvider)(Uri.https(tenant.shareDomain, '/$slug')),
        child: Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary,
                  height: 1.5,
                )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tenant = ref.watch(tenantProvider);
    ref.listen(customerProvider, (was, now) {
      if (was?.value == null && now.value != null) widget.onSignedIn?.call();
    });
    final verb = _join ? 'Join' : 'Log in';
    ButtonStyle outlined() => OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        );
    final emailField = TextField(
      key: const Key('email'),
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: _method == _Method.password ? TextInputAction.next : TextInputAction.send,
      onSubmitted: (_) => _method == _Method.link && !_busy ? _sendLink() : null,
      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
    );
    final others = TextButton(
      key: const Key('other-ways'),
      onPressed: () => setState(() {
        _method = null;
        _error = _status = null;
      }),
      child: const Text('Other ways to log in'),
    );

    final email = switch (_method) {
      null => <Widget>[
          OutlinedButton.icon(
            key: const Key('use-link'),
            style: outlined(),
            onPressed: () => setState(() => _method = _Method.link),
            icon: const Icon(Icons.mail_outline),
            label: Text('$verb with email'),
          ),
          if (!_join) ...[
            SizedBox(height: b.spacing.sm),
            OutlinedButton.icon(
              key: const Key('use-password'),
              style: outlined(),
              onPressed: () => setState(() => _method = _Method.password),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Log in with password'),
            ),
          ],
        ],
      _Method.link => <Widget>[
          emailField,
          SizedBox(height: b.spacing.sm),
          FilledButton(
            key: const Key('send-link'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _sendLink,
            child: const Text('Email me a sign-in link'),
          ),
          SizedBox(height: b.spacing.xs),
          Text('No password needed: the link we email signs you in.', textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: b.textMuted)),
          if (!widget.emailFirst) others,
          if (widget.emailFirst && !_join)
            TextButton(
              key: const Key('use-password'),
              onPressed: () => setState(() => _method = _Method.password),
              child: const Text('Have a password? Log in with it'),
            ),
        ],
      _Method.password => <Widget>[
          emailField,
          SizedBox(height: b.spacing.sm),
          TextField(
            key: const Key('password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _withPassword(),
            decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
          ),
          SizedBox(height: b.spacing.sm),
          FilledButton(
            key: const Key('password-sign-in'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _withPassword,
            child: const Text('Log in'),
          ),
          Wrap(alignment: WrapAlignment.spaceBetween, children: [
            others,
            TextButton(onPressed: _busy ? null : _reset, child: const Text('Forgot password?')),
          ]),
        ],
    };

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(b.spacing.xl, widget.closable ? b.spacing.sm : b.spacing.xl, b.spacing.xl, b.spacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (widget.closable)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(key: const Key('sign-in-close'), tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          ),
        Center(child: Image.asset(b.logoAsset, height: 56, filterQuality: FilterQuality.medium, semanticLabel: tenant.name)),
        SizedBox(height: b.spacing.md),
        Text(
          _join ? 'Create your ${tenant.name} account' : 'Log in to your ${tenant.name} account',
          key: const Key('sign-in-title'),
          textAlign: TextAlign.center,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: b.spacing.lg),
        OutlinedButton.icon(
          key: const Key('google'),
          style: outlined(),
          onPressed: _busy ? null : _google,
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: Text('$verb with Google'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: b.spacing.md),
          child: Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: b.spacing.md), child: Text('OR', style: text.labelSmall?.copyWith(color: b.textMuted))),
            const Expanded(child: Divider()),
          ]),
        ),
        ...email,
        if (_status != null) _Line(text: _status!, icon: Icons.mark_email_read_outlined, ink: scheme.primary, fill: b.primarySoft),
        if (_error != null) _Line(text: _error!, icon: Icons.error_outline, ink: scheme.error, fill: scheme.errorContainer.withValues(alpha: 0.4)),
        if (_join) ...[
          SizedBox(height: b.spacing.md),
          // One sentence with the two pages as links in it, as on Bayut.
          Text.rich(
            key: const Key('join-disclaimer'),
            TextSpan(children: [
              TextSpan(text: 'When creating a new account you agree to ${tenant.name} '),
              _link('Terms and conditions', 'terms', const Key('link-terms')),
              const TextSpan(text: ' and '),
              _link('Privacy Policy', 'privacy', const Key('link-privacy')),
              const TextSpan(text: '.'),
            ]),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: b.textMuted, height: 1.5),
          ),
        ],
        SizedBox(height: b.spacing.md),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_join ? 'Already have an account?' : 'New to ${tenant.name}?', style: text.bodyMedium),
          TextButton(
            key: const Key('auth-toggle'),
            onPressed: () => setState(() {
              _join = !_join;
              _error = _status = null;
              if (_join && _method == _Method.password) _method = widget.emailFirst ? _Method.link : null;
            }),
            child: Text(_join ? 'Log in' : 'Create an account'),
          ),
        ]),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.icon, required this.ink, required this.fill});
  final String text;
  final IconData icon;
  final Color ink, fill;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      margin: EdgeInsets.only(top: b.spacing.md),
      padding: EdgeInsets.all(b.spacing.md),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(b.radiusSm)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: ink, size: 20),
        SizedBox(width: b.spacing.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}
