import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../phone_nav.dart';
import '../providers.dart';
import '../saved/favourites.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final customer = ref.watch(customerProvider).value;
    final pendingAlert = ref.watch(pendingAlertProvider);
    final tenant = ref.watch(tenantProvider);
    final saved = ref.watch(favouritesProvider).value?.length ?? 0;
    final notes = <Widget>[
      if (_status != null) _Note(text: _status!, icon: Icons.mark_email_read_outlined),
      if (_error != null) _Note(text: _error!, icon: Icons.error_outline, error: true),
    ];
    Widget benefit(IconData icon, String title, String line) => Padding(
          padding: EdgeInsets.only(bottom: b.spacing.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
              child: Icon(icon, color: scheme.primary, size: 22),
            ),
            SizedBox(width: b.spacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: text.titleSmall),
                Text(line, style: text.bodySmall?.copyWith(color: b.textMuted)),
              ]),
            ),
          ]),
        );

    final signedOut = <Widget>[
      Text('Log in or sign up', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: b.spacing.xs),
      Text('Browsing and saving homes need no account. Sign in to keep them on every device and to hear about new homes first.',
          style: text.bodyMedium?.copyWith(color: b.textMuted)),
      SizedBox(height: b.spacing.lg),
      if (pendingAlert != null) ...[
        Card(
          color: b.primarySoft,
          child: ListTile(
            leading: Icon(Icons.notifications_active_outlined, color: scheme.primary),
            // What the alert will match: typed words are not part of alerts.
            title: Text('Sign in to get alerts for: ${describeSearch(filtersFromAlert(alertFilters(pendingAlert)))}'),
            subtitle: pendingAlert.q == null ? null : Text('Alerts match the filters, not the words "${pendingAlert.q}".'),
          ),
        ),
        SizedBox(height: b.spacing.lg),
      ],
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _busy ? null : _google,
        icon: const Icon(Icons.g_mobiledata, size: 28),
        label: const Text('Continue with Google'),
      ),
      Padding(
        padding: EdgeInsets.symmetric(vertical: b.spacing.md),
        child: Row(children: [
          const Expanded(child: Divider()),
          Padding(
              padding: EdgeInsets.symmetric(horizontal: b.spacing.md), child: Text('or with your email', style: text.bodySmall?.copyWith(color: b.textMuted))),
          const Expanded(child: Divider()),
        ]),
      ),
      TextField(
        key: const Key('email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _busy ? null : (_finishing ? _complete(_email.text.trim()) : _sendLink()),
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
      ),
      SizedBox(height: b.spacing.md),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _busy ? null : (_finishing ? () => _complete(_email.text.trim()) : _sendLink),
        child: Text(_finishing ? 'Finish signing in' : 'Email me a sign-in link'),
      ),
      SizedBox(height: b.spacing.xs),
      Text('No password: we email you a link that signs you in.', style: text.bodySmall?.copyWith(color: b.textMuted), textAlign: TextAlign.center),
      ...notes,
      SizedBox(height: b.spacing.xl),
      Text('With an account', style: text.titleMedium),
      SizedBox(height: b.spacing.md),
      benefit(Icons.favorite_border, 'Your saved homes, everywhere', 'Homes you save on this phone show on your computer too.'),
      benefit(Icons.notifications_active_outlined, 'Alerts for new homes', 'Save a search and hear as soon as a matching home is listed.'),
      benefit(Icons.rate_review_outlined, 'Reviews', 'Say what a home you lived in or viewed is like.'),
    ];

    final signedIn = customer == null
        ? const <Widget>[]
        : <Widget>[
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: b.primarySoft,
                child: Text((customer.email ?? '?').characters.first.toUpperCase(), style: text.titleLarge?.copyWith(color: scheme.primary)),
              ),
              SizedBox(width: b.spacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer.email ?? 'Signed in', style: text.titleMedium, overflow: TextOverflow.ellipsis),
                  Text('Signed in', style: text.bodySmall?.copyWith(color: b.textMuted)),
                ]),
              ),
            ]),
            SizedBox(height: b.spacing.lg),
            Row(children: [
              Expanded(child: _Stat(icon: Icons.favorite_border, label: 'Saved homes', value: '$saved', onTap: () => context.go('/saved'))),
              SizedBox(width: b.spacing.sm),
              Expanded(
                child: _Stat(
                  icon: Icons.search,
                  label: 'Saved searches',
                  value: '${ref.watch(savedSearchesProvider(customer.uid)).value?.length ?? 0}',
                ),
              ),
            ]),
            if (pendingAlert != null) ...[
              SizedBox(height: b.spacing.md),
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
            ...notes,
            SizedBox(height: b.spacing.lg),
            _Section(title: 'New homes for you', child: _Alerts(uid: customer.uid)),
            SizedBox(height: b.spacing.md),
            _Section(title: 'Saved searches', child: _Searches(uid: customer.uid)),
            SizedBox(height: b.spacing.md),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.logout),
              onPressed: () async {
                // This phone stops getting this account's pushes.
                try {
                  await ref.read(pushAlertsProvider).disable(customer.uid);
                } on Object {
                  // Signing out still works; the sweep forgets dead tokens.
                }
                await ref.read(customerAccountProvider).signOut();
              },
              label: const Text('Sign out'),
            ),
          ];

    final page = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
          ...(customer == null ? signedOut : signedIn),
          SizedBox(height: b.spacing.xl),
          const Divider(),
          // Site pages live on the share site (P5-s07); they open in the browser.
          Wrap(alignment: WrapAlignment.center, spacing: b.spacing.sm, children: [
            for (final (slug, name) in const [('about', 'About'), ('contact', 'Contact'), ('privacy', 'Privacy'), ('terms', 'Terms')])
              TextButton(onPressed: () => ref.read(urlOpenerProvider)(Uri.https(tenant.shareDomain, '/$slug')), child: Text(name)),
          ]),
        ]),
      ),
    );
    // Phones: the bar scrolls away with the page, as on the listing page.
    return usesScrollAwayBar(context) ? Scaffold(body: ScrollAwayBar.wrap(body: page)) : Scaffold(appBar: AppBar(title: const Text('Account')), body: page);
  }
}

/// A message under the sign-in form: what happened, or what went wrong.
class _Note extends StatelessWidget {
  const _Note({required this.text, required this.icon, this.error = false});
  final String text;
  final IconData icon;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final ink = error ? scheme.error : scheme.primary;
    return Container(
      margin: EdgeInsets.only(top: b.spacing.md),
      padding: EdgeInsets.all(b.spacing.md),
      decoration: BoxDecoration(color: error ? scheme.errorContainer.withValues(alpha: 0.4) : b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: ink, size: 20),
        SizedBox(width: b.spacing.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

/// A count to tap: saved homes, saved searches.
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(b.spacing.md),
          child: Row(children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            SizedBox(width: b.spacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(label, style: text.bodySmall?.copyWith(color: b.textMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A titled card on the Account page.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(b.spacing.md, b.spacing.md, b.spacing.md, b.spacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: b.spacing.sm),
          child,
        ]),
      ),
    );
  }
}

class _Alerts extends ConsumerWidget {
  const _Alerts({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final alerts = ref.watch(alertsProvider(uid)).value ?? const [];
    final repo = ref.read(alertsRepositoryProvider);
    if (alerts.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: b.spacing.sm),
        child: Row(children: [
          Icon(Icons.notifications_none, color: b.textMuted),
          SizedBox(width: b.spacing.sm),
          Expanded(child: Text('Nothing new yet. We check every few minutes.', style: text.bodyMedium?.copyWith(color: b.textMuted))),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final a in alerts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: a.read ? b.surfaceAlt : b.primarySoft,
            child: Icon(a.read ? Icons.home_outlined : Icons.fiber_new_outlined, color: a.read ? b.textMuted : scheme.primary),
          ),
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
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final searches = ref.watch(savedSearchesProvider(uid)).value ?? const [];
    if (searches.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: b.spacing.sm),
        child: Row(children: [
          Icon(Icons.search, color: b.textMuted),
          SizedBox(width: b.spacing.sm),
          Expanded(child: Text('Search for homes, then tap "Get alerts".', style: text.bodyMedium?.copyWith(color: b.textMuted))),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in searches)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: b.primarySoft, child: Icon(Icons.notifications_active_outlined, color: scheme.primary, size: 20)),
          title: Text(describeSearch(s.filters)),
          subtitle: Text(s.filters.types.isEmpty && s.filters.areas.isEmpty ? 'Any home, anywhere · alerts on' : 'Alerts on',
              style: text.bodySmall?.copyWith(color: b.textMuted)),
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
  const AlertButton({super.key, required this.filters, this.compact = false});
  final ListingFilters filters;

  /// "Save Search" as a plain text button, for the wide filter bar.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider).value;
    Future<void> save() async {
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
    }

    if (compact) {
      return TextButton(
        key: const Key('save-search'),
        style: TextButton.styleFrom(textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        onPressed: save,
        child: const Text('Save Search'),
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.notifications_active_outlined),
      label: const Text('Get alerts for new matches'),
      onPressed: save,
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
