import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../nav.dart';
import 'account_data.dart';

/// `/account/edit`, as Bayut's Edit Profile: the name and the WhatsApp
/// number (checked as a Kenyan mobile), the password (set or changed; not
/// for Google accounts), Save Changes, and deleting the account.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _whatsapp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  CustomerProfile? _profile;
  String? _error;
  bool _saving = false, _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(profileRepositoryProvider).load();
      _name.text = p.name ?? '';
      _whatsapp.text = p.whatsapp ?? '';
      if (mounted) setState(() => _profile = p);
    } on Object {
      if (mounted) setState(() => _error = 'Your profile could not be loaded. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _whatsapp, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Saves the name and number, then the password when one was typed.
  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final number = _whatsapp.text.trim().isEmpty ? '' : normaliseKenyanPhone(_whatsapp.text)!;
      await ref.read(profileRepositoryProvider).save(name: _name.text.trim(), whatsapp: number);
      if (_password.text.isNotEmpty) await ref.read(profileRepositoryProvider).setPassword(_password.text);
      _password.clear();
      _confirm.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Your changes are saved.')));
      if (mounted && context.canPop()) context.pop();
    } on SignInFailure catch (e) {
      setState(() => _error = e.code == 'requires-recent-login'
          ? 'For your safety, sign out and sign in again before changing your password.'
          : 'Your changes could not be saved. Please try again. (${e.code})');
    } on Object {
      setState(() => _error = 'Your changes could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('Your profile, saved searches and alerts are deleted for good, and you are signed out. '
            'Homes saved on this device stay on it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep my account')),
          FilledButton(
            key: const Key('confirm-delete'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      messenger.showSnackBar(const SnackBar(content: Text('Your account is deleted.')));
      router.go('/');
    } on Object {
      if (mounted) setState(() => _error = 'Your account could not be deleted just now. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final customer = ref.watch(customerProvider).value;
    final p = _profile;
    Widget section(String title, List<Widget> children) => Padding(
          padding: EdgeInsets.only(bottom: b.spacing.lg),
          child: Material(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(b.radiusMd),
            child: Padding(
              padding: EdgeInsets.all(b.spacing.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: b.spacing.md),
                ...children,
              ]),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: b.surfaceAlt,
      appBar: AppBar(leading: const AppBack(), centerTitle: true, title: const Text('Edit Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: _form,
                  child: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
                    section('Your details', [
                      TextFormField(
                        key: const Key('profile-name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                      ),
                      SizedBox(height: b.spacing.md),
                      TextFormField(
                        initialValue: customer?.email ?? '',
                        enabled: false,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                      ),
                      SizedBox(height: b.spacing.md),
                      TextFormField(
                        key: const Key('profile-whatsapp'),
                        controller: _whatsapp,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp number',
                          hintText: '0712 345 678',
                          helperText: 'So agents can reach you on WhatsApp. Leave empty if you prefer not.',
                          helperMaxLines: 2,
                          prefixIcon: Icon(Icons.chat_outlined),
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty || normaliseKenyanPhone(v!) != null ? null : 'Enter a Kenyan mobile number, e.g. 0712 345 678',
                      ),
                    ]),
                    if (p != null && !p.google)
                      section(p.hasPassword ? 'Change password' : 'Set a password', [
                        Text(
                          p.hasPassword
                              ? 'Choose a new password. You can still sign in with an emailed link.'
                              : 'Optional: with a password you can sign in without waiting for an emailed link.',
                          style: text.bodySmall?.copyWith(color: b.textMuted),
                        ),
                        SizedBox(height: b.spacing.md),
                        TextFormField(
                          key: const Key('profile-password'),
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_outline)),
                          validator: (v) => (v ?? '').isEmpty || v!.length >= 8 ? null : 'At least 8 characters',
                        ),
                        SizedBox(height: b.spacing.md),
                        TextFormField(
                          key: const Key('profile-password-confirm'),
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline)),
                          validator: (v) => (v ?? '') == _password.text ? null : 'The passwords do not match',
                        ),
                      ])
                    else if (p != null)
                      section('Password', [
                        Row(children: [
                          const Icon(Icons.g_mobiledata, size: 28),
                          SizedBox(width: b.spacing.sm),
                          Expanded(child: Text('You sign in with Google, so there is no password to set here.', style: text.bodyMedium)),
                        ]),
                      ]),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: b.spacing.md),
                        child: Text(_error!, style: text.bodyMedium?.copyWith(color: scheme.error)),
                      ),
                    FilledButton(
                      key: const Key('save-profile'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save Changes'),
                    ),
                    SizedBox(height: b.spacing.xl),
                    TextButton.icon(
                      key: const Key('delete-account'),
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete account'),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }
}
