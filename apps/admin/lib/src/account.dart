import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'providers.dart';
import 'session.dart';

/// The signed-in person's own account: their name and phone (shown to the
/// team, and the name in the audit log), and their password.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _name = TextEditingController(), _phone = TextEditingController();
  final _current = TextEditingController(), _next = TextEditingController(), _again = TextEditingController();
  bool _savingProfile = false, _savingPassword = false, _loaded = false;
  String? _profileError, _passwordError;

  static const minPassword = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final who = ref.read(staffProvider)!;
    _name.text = who.name;
    try {
      final me = await ref.read(adminRepositoryProvider).me(who);
      if (me?.phone != null) _phone.text = me!.phone!;
    } on Object {
      // No record yet: start blank.
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _current, _next, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final who = ref.read(staffProvider)!;
    final phone = _phone.text.trim().isEmpty ? null : normaliseKenyanPhone(_phone.text);
    if (_name.text.trim().length < 2) return setState(() => _profileError = 'Your name needs at least 2 letters.');
    if (_phone.text.trim().isNotEmpty && phone == null) {
      return setState(() => _profileError = 'That phone does not look like a Kenyan mobile (07…, 01… or +254…).');
    }
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminActionsProvider).saveMyProfile(who, name: _name.text.trim(), phone: phone);
      final auth = ref.read(adminAuthProvider);
      if (auth is DemoAuth) {
        auth.rename(_name.text.trim());
      } else {
        await auth.refresh();
      }
      if (phone != null) _phone.text = phone;
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } on AdminActionException catch (e) {
      setState(() => _profileError = "Couldn't save: ${e.message}");
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (_next.text.length < minPassword) return setState(() => _passwordError = 'Choose at least $minPassword characters.');
    if (_next.text != _again.text) return setState(() => _passwordError = 'The two new passwords are not the same.');
    if (_next.text == _current.text) return setState(() => _passwordError = 'The new password is the same as the current one.');
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminAuthProvider).changePassword(_current.text, _next.text);
      for (final c in [_current, _next, _again]) {
        c.clear();
      }
      messenger.showSnackBar(const SnackBar(content: Text('Password changed. Use the new one next time you sign in.')));
    } on SignInException catch (e) {
      setState(() => _passwordError = e.message);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final auth = ref.watch(adminAuthProvider);
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final initials = who.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    Widget card(String title, String subtitle, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(b.radiusMd + 4),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: text.bodySmall?.copyWith(color: b.textMuted)),
            const SizedBox(height: 20),
            ...children,
          ]),
        );

    return ListView(padding: const EdgeInsets.all(24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Account', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            card('Profile', 'Your name shows to the team and in the audit log.', [
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primary,
                  child: Text(initials, style: text.titleMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(who.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(auth.email ?? '', style: text.bodySmall?.copyWith(color: b.textMuted)),
                  ]),
                ),
                Chip(label: Text(roleLabel(who.role)), visualDensity: VisualDensity.compact),
              ]),
              const SizedBox(height: 20),
              TextField(
                key: const Key('account-name'),
                controller: _name,
                enabled: _loaded,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('account-phone'),
                controller: _phone,
                enabled: _loaded,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone', hintText: '0712 345 678', border: OutlineInputBorder()),
              ),
              if (_profileError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_profileError!, style: TextStyle(color: scheme.error))),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('account-save'),
                  onPressed: _savingProfile || !_loaded ? null : _saveProfile,
                  child: Text(_savingProfile ? 'Saving…' : 'Save profile'),
                ),
              ),
            ]),
            card(
              'Password',
              auth.hasPassword ? 'At least $minPassword characters. You stay signed in here.' : 'You sign in with Google.',
              auth.hasPassword
                  ? [
                      AutofillGroup(
                        child: Column(children: [
                          TextField(
                            key: const Key('password-current'),
                            controller: _current,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: const InputDecoration(labelText: 'Current password', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('password-new'),
                            controller: _next,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('password-again'),
                            controller: _again,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(labelText: 'New password again', border: OutlineInputBorder()),
                          ),
                        ]),
                      ),
                      if (_passwordError != null)
                        Padding(padding: const EdgeInsets.only(top: 12), child: Text(_passwordError!, style: TextStyle(color: scheme.error))),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const Key('password-change'),
                          onPressed: _savingPassword ? null : _changePassword,
                          child: Text(_savingPassword ? 'Changing…' : 'Change password'),
                        ),
                      ),
                    ]
                  : [Text('Your password is managed in your Google account, not here.', style: text.bodyMedium)],
            ),
            card('Sign out', 'Signs you out of the admin on this browser.', [
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(adminAuthProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
