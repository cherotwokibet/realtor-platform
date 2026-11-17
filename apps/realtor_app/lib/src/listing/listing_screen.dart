import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_data.dart';
import '../app.dart' show TopNav;
import '../providers.dart';
import '../sections.dart';
import '../site_footer.dart';
import 'gallery.dart';
import '../saved/favourites.dart';
import '../search/purpose.dart';
import '../search/results_screen.dart';
import 'lead_sheets.dart';
import '../nav.dart';

/// `/listing/<slug>`: the same page share links open on the web (P3-s03),
/// with call, WhatsApp, enquiry and viewing actions (P3-s06 in the app).
class ListingScreen extends ConsumerWidget {
  const ListingScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(listingDetailProvider(slug));
    return detail.when(
      loading: () => Scaffold(appBar: AppBar(leading: const AppBack()), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => _Message(text: 'This home could not be loaded. Check your connection and try again.'),
      data: (d) => d == null ? const _Message(text: 'This home is no longer available.') : _ListingView(detail: d),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: const AppBack()),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(context.brand.spacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              SizedBox(height: context.brand.spacing.lg),
              FilledButton(onPressed: () => context.go('/'), child: const Text('See all homes')),
            ]),
          ),
        ),
      );
}

/// The listing page, as on the big portals. Wide screens: the top menu, the
/// photo mosaic, then the details beside a contact card. Phones: the photos
/// to swipe, the details, and Call and WhatsApp fixed at the bottom. Both end
/// with homes like this one and the site footer.
class _ListingView extends ConsumerWidget {
  const _ListingView({required this.detail});
  final ListingDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final tenant = ref.watch(tenantProvider);
    final l = detail.summary;
    final wide = MediaQuery.sizeOf(context).width >= wideListingLayout;
    final items = galleryOf(detail);
    final phone = detail.agent?.phone ?? (tenant.hasContactNumbers ? tenant.phone : null);
    final whatsapp = detail.agent?.whatsapp ?? (tenant.hasContactNumbers ? tenant.whatsapp : null);
    final link = 'https://${tenant.shareDomain}/listing/${l.slug}';

    Future<void> contact(String channel, Uri uri) async {
      // Counting the tap (D13) must never stop the call or chat.
      ref.read(leadRepositoryProvider).logTap(listingId: l.id, channel: channel).ignore();
      if (!await ref.read(urlOpenerProvider)(uri) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app on this phone can open that.')));
      }
    }

    final actions = _ContactActions(
      call: phone == null ? null : () => contact('call', Uri(scheme: 'tel', path: phone)),
      whatsapp: whatsapp == null
          ? null
          : () => contact(
                'whatsapp',
                Uri.https('wa.me', '/${whatsapp.replaceAll('+', '')}', {'text': 'Hi, I saw "${l.title}" ($link). Is it still available?'}),
              ),
      email: () => showEnquirySheet(context, listing: l),
    );
    void openGallery({bool map = false}) => showGallery(context, items: items, title: l.title, contact: actions, lat: l.lat, lng: l.lng, map: map);

    // Phones have Call and WhatsApp in the bottom bar, so their card leaves them out.
    final body = _Body(detail: detail, link: link, wide: wide, contactCard: _ContactCard(detail: detail, actions: wide ? actions : null));
    final recommended = _Recommended(listing: l, wide: wide);

    if (wide) {
      final top = TopNav(
        sections: visibleSections(enabledSections(tenant.features), signedIn: ref.watch(customerProvider).value != null),
        location: '/${l.purpose.pathSegment}',
        width: resultsContentWidth,
        gutter: 24,
      );
      Widget page(Widget child) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: resultsContentWidth),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
            ),
          );
      return Scaffold(
        body: Scrollbar(
          thumbVisibility: true,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView(
              primary: true,
              children: [
                SizedBox(height: TopNav.height, child: top),
                page(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('back-to-search'),
                      onPressed: () => context.canPop() ? context.pop() : context.go('/${l.purpose.pathSegment}'),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Back to search'),
                    ),
                  ),
                  GalleryMosaic(
                    items: items,
                    title: l.title,
                    verified: l.verified,
                    onOpen: (_) => openGallery(),
                    onMap: () => openGallery(map: true),
                  ),
                  SizedBox(height: b.spacing.lg),
                  body,
                  recommended,
                  SizedBox(height: b.spacing.xxl),
                ])),
                const SiteFooter(width: resultsContentWidth),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBack(),
        actions: [
          IconButton(tooltip: 'Share', icon: const Icon(Icons.ios_share), onPressed: () => shareListing(context, link)),
          FavouriteButton(listing: l),
        ],
      ),
      // Call and WhatsApp stay in reach while the page scrolls.
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          child: Padding(padding: EdgeInsets.all(b.spacing.md), child: actions.copyWith(compact: true)),
        ),
      ),
      body: ListView(
        primary: true,
        children: [
          PhotoStrip(items: items, title: l.title, verified: l.verified, onOpen: (i) => showPhotoViewer(context, items: items, title: l.title, initial: i)),
          Padding(padding: EdgeInsets.all(b.spacing.gutter), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [body, recommended])),
          SizedBox(height: b.spacing.xl),
          const SiteFooter(),
        ],
      ),
    );
  }
}

/// From this width the listing has the photo mosaic and a contact column.
const wideListingLayout = 900.0;

/// Copies the listing's link, and says so.
Future<void> shareListing(BuildContext context, String link) async {
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Link copied. Paste it in a chat or a message.')));
  }
}

/// Call, WhatsApp and Email for this home, in that order, as the result cards
/// have them. [compact]: phones' bottom bar, Call and WhatsApp only (Email
/// stands in while there are no numbers).
class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.call, required this.whatsapp, required this.email, this.compact = false});
  final VoidCallback? call, whatsapp;
  final VoidCallback email;
  final bool compact;

  _ContactActions copyWith({bool? compact}) => _ContactActions(call: call, whatsapp: whatsapp, email: email, compact: compact ?? this.compact);

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    ButtonStyle solid(Color fill, Color ink) => FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: ink,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
        );
    final onGreen = ThemeData.estimateBrightnessForColor(b.success) == Brightness.dark ? scheme.surface : scheme.onSurface;
    final buttons = <Widget>[
      if (call != null)
        FilledButton.icon(style: solid(scheme.primary, scheme.onPrimary), onPressed: call, icon: const Icon(Icons.call, size: 18), label: const Text('Call')),
      if (whatsapp != null)
        FilledButton.icon(
            style: solid(b.success, onGreen),
            onPressed: whatsapp,
            icon: const WhatsAppIcon(size: 20),
            label: const Text('WhatsApp', maxLines: 1, softWrap: false)),
      if (!compact || (call == null && whatsapp == null))
        FilledButton.icon(
            style: solid(b.primarySoft, scheme.primary), onPressed: email, icon: const Icon(Icons.mail_outline, size: 18), label: const Text('Email')),
    ];
    return Row(children: [
      for (final (i, button) in buttons.indexed) ...[if (i > 0) SizedBox(width: b.spacing.sm), Expanded(child: button)],
    ]);
  }
}

/// Wide screens' right column: who lists the home, the contact buttons,
/// and a viewing or a written enquiry.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.detail, required this.actions});
  final ListingDetail detail;
  final _ContactActions? actions;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final l = detail.summary;
    return Card(
      key: const Key('contact-card'),
      child: Padding(
        padding: EdgeInsets.all(b.spacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (detail.agent != null) ...[
            Row(children: [
              CircleAvatar(child: Text(detail.agent!.name.characters.first)),
              SizedBox(width: b.spacing.md),
              Expanded(child: Text('Listed by ${detail.agent!.name}', style: text.titleSmall)),
            ]),
            SizedBox(height: b.spacing.md),
          ],
          // Call and WhatsApp side by side (the card is too narrow for a third),
          // then a viewing, then a written enquiry, which is the email.
          if (actions != null) ...[actions!.copyWith(compact: true), SizedBox(height: b.spacing.sm)],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.event_outlined),
            label: const Text('Book a viewing'),
            onPressed: () => showViewingSheet(context, listing: l),
          ),
          SizedBox(height: b.spacing.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Enquire'),
            onPressed: () => showEnquirySheet(context, listing: l),
          ),
        ]),
      ),
    );
  }
}

/// Everything about the home, in the portals' order: price with Share and
/// Save, the facts, the details, features, safety tips and extra payments,
/// the description and the map. Wide screens put the contact card beside it.
class _Body extends ConsumerWidget {
  const _Body({required this.detail, required this.link, required this.wide, required this.contactCard});
  final ListingDetail detail;
  final String link;
  final bool wide;
  final Widget contactCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tenant = ref.watch(tenantProvider);
    final l = detail.summary;
    final where = [if (detail.estate != null) detail.estate!, areaName(l.area)].join(', ');
    final section = SizedBox(height: b.spacing.xl);
    Widget heading(String s) => Padding(padding: EdgeInsets.only(bottom: b.spacing.md), child: Text(s, style: text.titleLarge));
    Widget fact(IconData icon, String value) => Padding(
          padding: EdgeInsets.only(right: b.spacing.lg),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(icon, size: 20, color: b.textMuted), SizedBox(width: b.spacing.xs), Text(value, style: text.bodyLarge)]),
        );
    final saved = (ref.watch(favouritesProvider).value ?? const []).any((x) => x.id == l.id);
    final tinted = FilledButton.styleFrom(
        backgroundColor: b.primarySoft, foregroundColor: scheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)));

    final main = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: PriceText(l.priceKES, period: l.purpose.period, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (wide) ...[
          FilledButton.icon(
              key: const Key('share'),
              style: tinted,
              onPressed: () => shareListing(context, link),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Share')),
          SizedBox(width: b.spacing.sm),
          FilledButton.icon(
            key: const Key('save'),
            style: tinted,
            onPressed: () => ref.read(favouritesProvider.notifier).toggle(l),
            icon: Icon(saved ? Icons.favorite : Icons.favorite_border, size: 18),
            label: Text(saved ? 'Saved' : 'Save'),
          ),
        ],
      ]),
      SizedBox(height: b.spacing.sm),
      Wrap(runSpacing: b.spacing.xs, children: [
        fact(Icons.home_outlined, typeName(l.type)),
        if (l.beds > 0) fact(Icons.bed_outlined, '${l.beds} ${l.beds == 1 ? 'bed' : 'beds'}'),
        if (l.baths > 0) fact(Icons.bathtub_outlined, '${l.baths} ${l.baths == 1 ? 'bath' : 'baths'}'),
      ]),
      SizedBox(height: b.spacing.sm),
      Text(l.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: b.spacing.xs),
      Row(children: [
        Icon(Icons.place_outlined, size: 18, color: b.textMuted),
        SizedBox(width: b.spacing.xs),
        Expanded(child: Text(where, style: text.bodyMedium))
      ]),
      if (!wide) ...[SizedBox(height: b.spacing.lg), contactCard],
      section,
      heading('Property details'),
      _DetailsTable(detail: detail, wide: wide),
      if (l.amenities.isNotEmpty) ...[
        section,
        heading('Features & amenities'),
        Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
          for (final a in l.amenities) Chip(avatar: Icon(Icons.check_circle_outline, size: 18, color: scheme.primary), label: Text(typeName(a))),
        ]),
      ],
      section,
      const _SafetyTips(),
      _ExtraPayments(detail: detail, mpesa: tenant.features.isOn(Feature.mpesa)),
      if (detail.description.trim().isNotEmpty) ...[section, heading('Description'), _Description(text: detail.description.trim())],
      section,
      heading('Location'),
      Text(where, style: text.bodyMedium),
      SizedBox(height: b.spacing.md),
      ClipRRect(
        borderRadius: BorderRadius.circular(b.radiusMd),
        child: SizedBox(height: wide ? 360 : 240, child: ListingMap(lat: l.lat, lng: l.lng, title: l.title)),
      ),
    ]);
    if (!wide) return main;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: main),
      const SizedBox(width: 25),
      SizedBox(width: 300, child: contactCard),
    ]);
  }
}

/// The facts in two columns, each with its icon.
class _DetailsTable extends ConsumerWidget {
  const _DetailsTable({required this.detail, required this.wide});
  final ListingDetail detail;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final l = detail.summary;
    String ago(DateTime t) {
      final days = ref.read(clockProvider)().difference(t).inDays;
      return days <= 0
          ? 'Today'
          : days == 1
              ? 'Yesterday'
              : days < 31
                  ? '$days days ago'
                  : days < 365
                      ? '${days ~/ 30} months ago'
                      : 'Over a year ago';
    }

    String utility(String key) => detail.utilities[key]! ? 'Included' : 'Paid separately';
    final rows = <(IconData, String, String)>[
      (Icons.home_outlined, 'Property type', typeName(l.type)),
      (Icons.sell_outlined, 'Purpose', l.purpose.label),
      if (l.beds > 0) (Icons.bed_outlined, 'Bedrooms', '${l.beds}'),
      if (l.baths > 0) (Icons.bathtub_outlined, 'Bathrooms', '${l.baths}'),
      (Icons.chair_outlined, 'Furnishing', l.amenities.any((a) => a.toLowerCase() == 'furnished') ? 'Furnished' : 'Unfurnished'),
      if (detail.listedAt != null) (Icons.schedule, 'Listed', ago(detail.listedAt!)),
      if (l.verified) (Icons.verified_outlined, 'Verified', 'Re-confirmed in the last 30 days'),
      for (final (key, name, icon) in const [
        ('water', 'Water', Icons.water_drop_outlined),
        ('electricity', 'Electricity', Icons.bolt_outlined),
        ('wifi', 'Wi-Fi', Icons.wifi)
      ])
        if (detail.utilities.containsKey(key)) (icon, name, utility(key)),
    ];
    Widget row((IconData, String, String) r) => Padding(
          padding: EdgeInsets.symmetric(vertical: b.spacing.sm),
          child: Row(children: [
            Icon(r.$1, size: 20, color: b.textMuted),
            SizedBox(width: b.spacing.sm),
            Expanded(child: Text(r.$2, style: text.bodyMedium?.copyWith(color: b.textMuted))),
            Expanded(child: Text(r.$3, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          ]),
        );
    if (!wide) return Column(key: const Key('property-details'), children: [for (final r in rows) row(r)]);
    final half = (rows.length + 1) ~/ 2;
    return Row(key: const Key('property-details'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(children: [for (final r in rows.take(half)) row(r)])),
      SizedBox(width: b.spacing.xl),
      Expanded(child: Column(children: [for (final r in rows.skip(half)) row(r)])),
    ]);
  }
}

/// Plain advice, the same on every listing, so nobody pays for a home they
/// have not seen.
class _SafetyTips extends StatelessWidget {
  const _SafetyTips();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const tips = [
      'Always visit the home before you pay anything.',
      "Don't rush into paying for a home.",
      'Pay only to the official M-Pesa or bank details on the agreement, never to a personal number.',
    ];
    return Container(
      key: const Key('safety-tips'),
      width: double.infinity,
      padding: EdgeInsets.all(b.spacing.lg),
      decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield_outlined, color: scheme.primary),
          SizedBox(width: b.spacing.sm),
          Expanded(child: Text('Tips for your safety', style: text.titleMedium)),
        ]),
        SizedBox(height: b.spacing.sm),
        for (final t in tips)
          Padding(
            padding: EdgeInsets.only(top: b.spacing.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_circle, size: 18, color: scheme.primary),
              SizedBox(width: b.spacing.sm),
              Expanded(child: Text(t, style: text.bodyMedium)),
            ]),
          ),
      ]),
    );
  }
}

/// What is paid on top of the price: the deposit, a service charge, a
/// viewing fee. Nothing when there is none.
class _ExtraPayments extends StatelessWidget {
  const _ExtraPayments({required this.detail, required this.mpesa});
  final ListingDetail detail;
  final bool mpesa;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final l = detail.summary;
    final months = detail.depositMonths;
    final rows = <(String, String)>[
      if (months != null && months > 0) ('Deposit', '$months month${months == 1 ? '' : 's'} · ${formatKes(months * l.priceKES)}'),
      if ((detail.serviceChargeKES ?? 0) > 0) ('Service charge', '${formatKes(detail.serviceChargeKES!)} a month'),
      if (mpesa && (detail.viewingFeeKES ?? 0) > 0) ('Viewing fee', '${formatKes(detail.viewingFeeKES!)}, by M-Pesa after you book'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('extra-payments'),
      padding: EdgeInsets.only(top: b.spacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Extra payments', style: text.titleMedium),
        SizedBox(height: b.spacing.sm),
        for (final (name, value) in rows)
          Padding(
            padding: EdgeInsets.symmetric(vertical: b.spacing.xs),
            child: Row(children: [
              Expanded(child: Text(name, style: text.bodyMedium)),
              Flexible(child: Text(value, textAlign: TextAlign.end, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }
}

/// The agent's words; long ones open with "Read more".
class _Description extends StatefulWidget {
  const _Description({required this.text});
  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6);
    final long = widget.text.length > 500;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        alignment: Alignment.topCenter,
        child: Text(widget.text, style: style, maxLines: long && !_open ? 8 : null, overflow: long && !_open ? TextOverflow.fade : null),
      ),
      if (long) TextButton(onPressed: () => setState(() => _open = !_open), child: Text(_open ? 'Read less' : 'Read more')),
    ]);
  }
}

/// Homes like this one (P7-s04): from the same area and the newest of the
/// same purpose, in a row to scroll through; nothing while loading or when
/// none are close.
class _Recommended extends ConsumerStatefulWidget {
  const _Recommended({required this.listing, required this.wide});
  final ListingSummary listing;
  final bool wide;

  @override
  ConsumerState<_Recommended> createState() => _RecommendedState();
}

class _RecommendedState extends ConsumerState<_Recommended> {
  /// The listing the section was last counted as shown for.
  String? _counted;
  final _row = ScrollController();

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  /// Click-through counts (P7-s04) are best effort: a failed count never
  /// gets in the way of the page.
  void _log(String event) => ref.read(leadRepositoryProvider).logRecommendation(listingId: widget.listing.id, event: event).catchError((Object _) {});

  void _scroll(double by) {
    if (!_row.hasClients) return;
    _row.animateTo((_row.offset + by).clamp(0, _row.position.maxScrollExtent), duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final inArea = ref.watch(liveListingsProvider((area: listing.area, agent: null))).value ?? const [];
    final newest = ref.watch(searchResultsProvider(ListingFilters(purpose: listing.purpose))).value?.hits ?? const [];
    final similar = similarListings(listing, [...inArea, ...newest], similarKey, count: 8);
    if (similar.isEmpty) return const SizedBox.shrink();
    if (_counted != listing.id) {
      _counted = listing.id;
      _log('shown');
    }
    final b = context.brand;
    const cardWidth = 300.0;
    return Padding(
      key: const Key('recommended'),
      padding: EdgeInsets.only(top: b.spacing.xxl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Recommended for you', style: Theme.of(context).textTheme.titleLarge)),
          if (widget.wide && similar.length > 1) ...[
            IconButton(tooltip: 'Previous homes', onPressed: () => _scroll(-(cardWidth + 16) * 2), icon: const Icon(Icons.chevron_left)),
            IconButton(tooltip: 'More homes', onPressed: () => _scroll((cardWidth + 16) * 2), icon: const Icon(Icons.chevron_right)),
          ],
        ]),
        SizedBox(height: b.spacing.md),
        SingleChildScrollView(
          controller: _row,
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, s) in similar.indexed) ...[
              if (i > 0) const SizedBox(width: 16),
              SizedBox(width: cardWidth, child: ListingCard(listing: s, onOpen: () => _log('opened'))),
            ],
          ]),
        ),
      ]),
    );
  }
}
