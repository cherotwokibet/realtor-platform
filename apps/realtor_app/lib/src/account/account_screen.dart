import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import '../search/purpose.dart';
import 'account_data.dart';
import 'push.dart';

/// The address the app was opened at (an emailed sign-in link lands here).
final openedAtProvider = Provider<Uri>((ref) => Uri.base);

/// Where the email typed for a sign-in link is kept until the link is opened.
abstract interface class PendingEmail {
  Future<String?> read();
  Future<void> write(String? email);
}

class PrefsPendingEmail implements PendingEmail {
  static const key = 'signin_email';
  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String? email) async {
    final p = await SharedPreferences.getInstance();
    email == null ? await p.remove(key) : await p.setString(key, email);
  }
}

final pendingEmailProvider = Provider<PendingEmail>((ref) => PrefsPendingEmail());

/// The search someone tapped "Get alerts" on before signing in: Account
/// offers it again once they are in, so they need not go back to it.
class PendingAlert extends Notifier<ListingFilters?> {
  @override
  ListingFilters? build() => null;
  void set(ListingFilters? f) => state = f;
}

final pendingAlertProvider = NotifierProvider<PendingAlert, ListingFilters?>(PendingAlert.new);

/// A search's name in a list: "Rent · apartment · Kilimani · up to KES 60,000".
String describeSearch(ListingFilters f) => [
      label(f.purpose),
      ...f.types.map(typeName),
      ...f.areas.map(areaName),
      if (f.minBeds != null) '${f.minBeds}+ bed',
      if (f.maxPriceKES != null) 'up to ${formatKes(f.maxPriceKES!)}',
    ].join(' · ');

String label(Purpose p) => switch (p) { Purpose.rent => 'Rent', Purpose.sale => 'Buy', Purpose.shortStay => 'Short stay' };

/// `/account` (D18): no account is needed to browse or save homes; one is
/// needed for alerts when new homes match a saved search.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, this.emailLink});

  /// An emailed sign-in link that opened the app (phones: /__/auth/links).
  final String? emailLink;
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  String? _status, _error;
  bool _busy = false, _finishing = false;

  @override
  void initState() {
    super.initState();
    _finishLink();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AccountScreen old) {
    super.didUpdateWidget(old);
    // A link tapped while Account was already open.
    if (widget.emailLink != old.emailLink) _finishLink();
  }

  /// The web page's own address, or the link that opened the app.
  Uri get _link => widget.emailLink != null ? Uri.parse(widget.emailLink!) : ref.read(openedAtProvider);

  bool get _isLink {
    final q = emailLinkFrom(_link).queryParameters;
    return q['mode'] == 'signIn' && q.containsKey('oobCode');
  }

  /// Opened from the emailed link: finish signing in with the stored email,
  /// or ask for it (another browser).
  Future<void> _finishLink() async {
    if (!_isLink) return;
    final stored = await ref.read(pendingEmailProvider).read();
    if (stored == null) {
      setState(() => _finishing = true);
      return;
    }
    await _complete(stored);
  }

  Future<void> _complete(String email) async {
    setState(() => _busy = true);
    try {
      final ok = await ref.read(customerAccountProvider).completeSignInLink(_link, email);
      await ref.read(pendingEmailProvider).write(null);
      if (mounted) setState(() => _status = ok ? 'Signed in.' : null);
      if (mounted && ok) context.go('/account');
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'That link did not work. It may be old; ask for a new one.${_code(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The provider's reason, small, for reports from phones.
  static String _code(Object e) => e is SignInFailure ? ' (${e.code})' : '';

  Future<void> _sendLink() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter your email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The link opens the web app's Account page (on a phone, the browser).
      final here = ref.read(openedAtProvider);
      final back = here.isScheme('http') || here.isScheme('https')
          ? here.replace(path: '/account', query: '')
          : Uri.https(ref.read(tenantProvider).appDomain, '/account');
      await ref.read(pendingEmailProvider).write(email);
      await ref.read(customerAccountProvider).sendSignInLink(email, back);
      if (mounted) setState(() => _status = 'Check $email for a sign-in link. Open it on this phone or computer.');
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'We could not send the link just now. Please try again.${_code(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _error = null);
    try {
      await ref.read(customerAccountProvider).signInWithGoogle();
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Google sign-in is not available here yet. Use the email link.${_code(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final customer = ref.watch(customerProvider).value;
    final pendingAlert = ref.watch(pendingAlertProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
        if (customer == null) ...[
          Text('Get alerts for new homes', style: text.titleLarge),
          if (pendingAlert != null) ...[
            SizedBox(height: b.spacing.sm),
            Card(
              color: b.primarySoft,
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                // What the alert will match: typed words are not part of alerts.
                title: Text('Sign in to get alerts for: ${describeSearch(filtersFromAlert(alertFilters(pendingAlert)))}'),
                subtitle: pendingAlert.q == null ? null : Text('Alerts match the filters, not the words "${pendingAlert.q}".'),
              ),
            ),
          ],
          SizedBox(height: b.spacing.sm),
          Text('You can browse and save homes without an account. Sign in to be told when new homes match a search you save.',
              style: text.bodyMedium),
          SizedBox(height: b.spacing.lg),
          TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          SizedBox(height: b.spacing.md),
          FilledButton(
            onPressed: _busy ? null : (_finishing ? () => _complete(_email.text.trim()) : _sendLink),
            child: Text(_finishing ? 'Finish signing in' : 'Email me a sign-in link'),
          ),
          SizedBox(height: b.spacing.sm),
          OutlinedButton(onPressed: _busy ? null : _google, child: const Text('Continue with Google')),
        ] else ...[
          Text(customer.email ?? 'Signed in', style: text.titleMedium),
          TextButton(
            onPressed: () async {
              // This phone stops getting this account's pushes.
              try {
                await ref.read(pushAlertsProvider).disable(customer.uid);
              } on Object {
                // Signing out still works; the sweep forgets dead tokens.
              }
              await ref.read(customerAccountProvider).signOut();
            },
            child: const Text('Sign out'),
          ),
          if (pendingAlert != null) ...[
            FilledButton.icon(
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text('Get alerts for ${describeSearch(filtersFromAlert(alertFilters(pendingAlert)))}'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(alertsRepositoryProvider).saveSearch(customer.uid, pendingAlert);
                ref.read(pendingAlertProvider.notifier).set(null);
                messenger.showSnackBar(
                    SnackBar(content: Text('Saved: ${describeSearch(filtersFromAlert(alertFilters(pendingAlert)))}. New matches will show here.')));
                await offerPush(ref, customer.uid);
              },
            ),
          ],
          SizedBox(height: b.spacing.md),
          _Alerts(uid: customer.uid),
          SizedBox(height: b.spacing.lg),
          _Searches(uid: customer.uid),
        ],
        if (_status != null) Padding(padding: EdgeInsets.only(top: b.spacing.md), child: Text(_status!, style: text.bodyMedium)),
        SizedBox(height: b.spacing.xl),
        // Site pages live on the share site (P5-s07); they open in the browser.
        Wrap(spacing: b.spacing.sm, children: [
          for (final (slug, name) in const [('about', 'About'), ('privacy', 'Privacy'), ('terms', 'Terms')])
            TextButton(
              onPressed: () => ref.read(urlOpenerProvider)(Uri.https(ref.read(tenantProvider).shareDomain, '/$slug')),
              child: Text(name),
            ),
        ]),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: b.spacing.md),
            child: Text(_error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
          ),
      ]),
    );
  }
}

class _Alerts extends ConsumerWidget {
  const _Alerts({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final alerts = ref.watch(alertsProvider(uid)).value ?? const [];
    final repo = ref.read(alertsRepositoryProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('New homes for you', style: text.titleMedium),
      if (alerts.isEmpty) Text('Nothing new yet. We check every few minutes.', style: text.bodySmall),
      for (final a in alerts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(a.read ? Icons.home_outlined : Icons.fiber_new_outlined),
          title: Text(a.title, style: a.read ? null : const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: PriceText(a.priceKES, period: a.purpose.period, compact: a.purpose == Purpose.sale),
          trailing: IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => repo.clear(uid, a.id)),
          onTap: () {
            repo.markRead(uid, a.id);
            context.push('/listing/${a.slug}');
          },
        ),
    ]);
  }
}

class _Searches extends ConsumerWidget {
  const _Searches({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final searches = ref.watch(savedSearchesProvider(uid)).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Saved searches', style: text.titleMedium),
      if (searches.isEmpty) Text('Search for homes, then tap "Get alerts".', style: text.bodySmall),
      for (final s in searches)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(describeSearch(s.filters)),
          onTap: () => context.push(s.filters.toUri().toString()),
          trailing: IconButton(
            tooltip: 'Stop these alerts',
            icon: const Icon(Icons.notifications_off_outlined),
            onPressed: () => ref.read(alertsRepositoryProvider).deleteSearch(s.id),
          ),
        ),
    ]);
  }
}

/// On results: save this search for alerts, or sign in first.
class AlertButton extends ConsumerWidget {
  const AlertButton({super.key, required this.filters});
  final ListingFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider).value;
    return OutlinedButton.icon(
      icon: const Icon(Icons.notifications_active_outlined),
      label: const Text('Get alerts for new matches'),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        if (customer == null) {
          // Account shows this search and offers it again after sign-in.
          ref.read(pendingAlertProvider.notifier).set(filters);
          context.go('/account');
          return;
        }
        await ref.read(alertsRepositoryProvider).saveSearch(customer.uid, filters);
        messenger.showSnackBar(SnackBar(content: Text('Saved: ${describeSearch(filters)}. New matches will show in Account.')));
        await offerPush(ref, customer.uid);
      },
    );
  }
}

/// After a search is saved: on phones, ask once to send push alerts too.
/// The inbox works either way, so a refusal or an error changes nothing.
Future<void> offerPush(WidgetRef ref, String uid) async {
  try {
    await ref.read(pushAlertsProvider).enable(uid);
  } on Object {
    // In-app alerts still arrive.
  }
}
