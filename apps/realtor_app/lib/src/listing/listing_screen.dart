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
    void openGallery({bool map = false, int at = 0}) => showGallery(context,
        items: items, title: l.title, contact: _GalleryContact(agent: detail.agent, actions: actions), lat: l.lat, lng: l.lng, map: map, initial: at);
    // The Video button plays the video at once, full size, with no extra step.
    void playVideo(int at) => showPhotoViewer(context, items: items, title: l.title, initial: at, autoplay: true);

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
                  _Breadcrumbs(detail: detail),
                  GalleryMosaic(
                    items: items,
                    title: l.title,
                    verified: l.verified,
                    onOpen: (i) => openGallery(at: i),
                    onMap: () => openGallery(map: true),
                    onVideo: playVideo,
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
      // As on the big portals' apps: back, the logo in the middle, Share and Save.
      appBar: AppBar(
        leading: const AppBack(),
        centerTitle: true,
        title: GestureDetector(
          onTap: () => context.go('/'),
          child: Image.asset(b.logoAsset, height: 40, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
        ),
        actions: [
          IconButton(tooltip: 'Share', icon: const Icon(Icons.ios_share), onPressed: () => shareListing(context, link)),
          FavouriteButton(listing: l),
        ],
      ),
      // Call and WhatsApp stay in reach while the page scrolls.
      bottomNavigationBar: SafeArea(
        child: Material(
          key: const Key('contact-bar'),
          elevation: 8,
          child: Padding(padding: EdgeInsets.all(b.spacing.md), child: actions.copyWith(compact: true)),
        ),
      ),
      body: ListView(
        primary: true,
        children: [
          PhotoStrip(
            items: items,
            title: l.title,
            verified: l.verified,
            onOpen: (i) => showPhotoViewer(context, items: items, title: l.title, initial: i, autoplay: items[i].video != null),
            onWhatsApp: whatsapp == null
                ? null
                : () =>
                    contact('whatsapp', Uri.https('wa.me', '/${whatsapp.replaceAll('+', '')}', {'text': 'Hi, I saw "${l.title}" ($link). I have a question.'})),
          ),
          Padding(padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.sm, b.spacing.gutter, 0), child: _Breadcrumbs(detail: detail, compact: true)),
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
    // Soft buttons, as on the big portals: a light tint of each colour with
    // the icon and the word in the colour itself.
    ButtonStyle soft(Color ink) => FilledButton.styleFrom(
          backgroundColor: ink.withValues(alpha: 0.1),
          foregroundColor: ink,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: EdgeInsets.symmetric(horizontal: b.spacing.sm),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
        );
    final buttons = <Widget>[
      if (call != null) FilledButton.icon(style: soft(scheme.primary), onPressed: call, icon: const Icon(Icons.call, size: 20), label: const Text('Call')),
      if (whatsapp != null)
        FilledButton.icon(
            style: soft(b.success), onPressed: whatsapp, icon: const WhatsAppIcon(size: 22), label: const Text('WhatsApp', maxLines: 1, softWrap: false)),
      if (!compact || (call == null && whatsapp == null))
        FilledButton.icon(style: soft(scheme.primary), onPressed: email, icon: const Icon(Icons.mail, size: 20), label: const Text('Email')),
    ];
    return Row(children: [
      for (final (i, button) in buttons.indexed) ...[if (i > 0) SizedBox(width: b.spacing.sm), Expanded(child: button)],
    ]);
  }
}

/// The foot of the gallery window, as on the big portals: who lists the
/// home on the left, the contact buttons on the right.
class _GalleryContact extends StatelessWidget {
  const _GalleryContact({required this.agent, required this.actions});
  final ListingAgent? agent;
  final _ContactActions actions;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    if (agent == null) return actions;
    return Row(children: [
      CircleAvatar(radius: 22, child: Text(agent!.name.characters.first)),
      SizedBox(width: b.spacing.md),
      Expanded(
        child: Text.rich(
          TextSpan(
              text: 'Listing by ',
              children: [TextSpan(text: agent!.name, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))]),
          style: text.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      SizedBox(width: b.spacing.md),
      SizedBox(width: 440, child: actions),
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
        _Amenities(amenities: l.amenities, wide: wide),
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
        child: SizedBox(height: wide ? 360 : 260, child: ListingMap(lat: l.lat, lng: l.lng, title: l.title)),
      ),
      section,
      _Reviews(listing: l),
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
    // Each tip with an icon that says it at a glance.
    const tips = [
      (Icons.directions_walk, 'Always visit the home before you pay anything.'),
      (Icons.hourglass_bottom, "Don't rush into paying for a home."),
      (Icons.receipt_long_outlined, 'Pay only to the official M-Pesa or bank details on the agreement, never to a personal number.'),
    ];
    return Container(
      key: const Key('safety-tips'),
      width: double.infinity,
      padding: EdgeInsets.all(b.spacing.lg),
      decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.health_and_safety_outlined, color: scheme.onPrimary, size: 20),
          ),
          SizedBox(width: b.spacing.sm),
          Expanded(child: Text('Tips for your safety', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        SizedBox(height: b.spacing.sm),
        for (final (icon, t) in tips)
          Padding(
            padding: EdgeInsets.only(top: b.spacing.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: scheme.primary),
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
    final close = similarListings(listing, [...inArea, ...newest], similarKey, count: 8);
    // Top the row up with the newest homes of the same purpose, so there is
    // always a row to browse, closest first.
    final similar = [
      ...close,
      for (final n in [...inArea, ...newest])
        if (n.id != listing.id && n.purpose == listing.purpose && !close.any((c) => c.id == n.id)) n,
    ].fold<List<ListingSummary>>([], (all, n) => all.any((a) => a.id == n.id) || all.length >= 10 ? all : [...all, n]);
    if (similar.isEmpty) return const SizedBox.shrink();
    if (_counted != listing.id) {
      _counted = listing.id;
      _log('shown');
    }
    final b = context.brand;
    const cardWidth = 264.0;
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
              SizedBox(width: cardWidth, child: RecommendedCard(listing: s, onOpen: () => _log('opened'))),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Where the home sits, as on the big portals: Back to search, then Home >
/// the type to rent (or buy) > the area > the estate > the home. Each but
/// the last opens that search.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.detail, this.compact = false});
  final ListingDetail detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = detail.summary;
    final typePath = listingTypeSlugs[l.type];
    final kind = typePath == null ? 'Homes' : '${typeName(l.type)}s';
    final purposeUrl = '/${l.purpose.pathSegment}';
    final crumbs = <(String, String?)>[
      ('$kind ${l.purpose.heading}', typePath == null ? purposeUrl : '$purposeUrl/$typePath'),
      (areaName(l.area), typePath == null ? '$purposeUrl/${l.area}' : '$purposeUrl/$typePath/${l.area}'),
      if (detail.estate != null && detail.estate!.trim().isNotEmpty) (detail.estate!.trim(), null),
      (l.title, null),
    ];
    final style = (compact ? text.bodySmall : text.bodyMedium);
    Widget chevron() => Padding(padding: EdgeInsets.symmetric(horizontal: b.spacing.xs), child: Icon(Icons.chevron_right, size: 16, color: b.textMuted));
    final trail = <Widget>[
      if (!compact) ...[
        TextButton.icon(
          key: const Key('back-to-search'),
          style: TextButton.styleFrom(padding: EdgeInsets.only(right: b.spacing.sm)),
          onPressed: () => context.canPop() ? context.pop() : context.go(purposeUrl),
          icon: const Icon(Icons.chevron_left),
          label: const Text('Back to search'),
        ),
        SizedBox(width: b.spacing.md),
      ],
      InkWell(onTap: () => context.go('/'), child: Icon(Icons.home_outlined, size: 18, color: scheme.primary, semanticLabel: 'Home')),
      for (final (i, (label, url)) in crumbs.indexed) ...[
        chevron(),
        url == null
            ? Text(label, style: style?.copyWith(fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : null), maxLines: 1, overflow: TextOverflow.ellipsis)
            : InkWell(onTap: () => context.go(url), child: Text(label, style: style?.copyWith(color: scheme.primary))),
      ],
    ];
    return SingleChildScrollView(
      key: const Key('breadcrumbs'),
      scrollDirection: Axis.horizontal,
      child: Padding(
        // Air above and below, as on the big portals.
        padding: compact ? EdgeInsets.zero : EdgeInsets.only(top: b.spacing.lg, bottom: b.spacing.md),
        child: Row(children: trail),
      ),
    );
  }
}

/// A smaller card for the Recommended row, as on the big portals: the photo
/// with the heart and the badge, the price, beds and baths, the place, and
/// Call and WhatsApp.
class RecommendedCard extends ConsumerWidget {
  const RecommendedCard({super.key, required this.listing, this.onOpen});
  final ListingSummary listing;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = listing;
    final photos = l.photos.isNotEmpty ? l.photos : [if (l.thumb != null) l.thumb!];
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          onOpen?.call();
          context.push('/listing/${l.slug}');
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              PhotoCarousel(photos: photos, label: l.title, videoPoster: l.videoPoster),
              if (l.verified) Positioned(left: b.spacing.sm, top: b.spacing.sm, child: const VerifiedBadge()),
              Positioned(right: 2, top: 2, child: Material(color: scheme.surface, shape: const CircleBorder(), child: FavouriteButton(listing: l))),
            ]),
          ),
          Padding(
            padding: EdgeInsets.all(b.spacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PriceText(l.priceKES,
                  period: l.purpose.period, compact: l.purpose == Purpose.sale, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: b.spacing.xs),
              Row(children: [
                Icon(Icons.bed_outlined, size: 16, color: b.textMuted),
                SizedBox(width: b.spacing.xs),
                Text(l.beds > 0 ? '${l.beds}' : typeName(l.type), style: text.bodySmall),
                if (l.baths > 0) ...[
                  SizedBox(width: b.spacing.md),
                  Icon(Icons.bathtub_outlined, size: 16, color: b.textMuted),
                  SizedBox(width: b.spacing.xs),
                  Text('${l.baths}', style: text.bodySmall),
                ],
                if (l.beds > 0) ...[
                  SizedBox(width: b.spacing.md),
                  Flexible(child: Text(typeName(l.type), style: text.bodySmall, overflow: TextOverflow.ellipsis))
                ],
              ]),
              SizedBox(height: b.spacing.xs),
              Text(l.title, style: text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(areaName(l.area), style: text.bodySmall?.copyWith(color: b.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: b.spacing.sm),
              ContactButtons(listing: l, expand: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// What people said about this home: the average and the approved reviews,
/// and a way to write one. Any signed-in visitor may; a manager checks each
/// before it shows, so the section never fills with spam or abuse.
class _Reviews extends ConsumerWidget {
  const _Reviews({required this.listing});
  final ListingSummary listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final reviews = ref.watch(reviewsForListingProvider(listing.id)).value ?? const <ListingReview>[];
    final average = averageRating(reviews);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    Widget stars(num value, {double size = 18}) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++) Icon(value >= i ? Icons.star : (value >= i - 0.5 ? Icons.star_half : Icons.star_border), size: size, color: b.accent),
        ]);
    Future<void> write() async {
      final signedIn = ref.read(customerProvider).value != null;
      if (!signedIn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Sign in to review this home.'),
            action: SnackBarAction(label: 'Sign in', onPressed: () => context.go('/account')),
          ));
        return;
      }
      // Phones: a sheet that rises above the keyboard; computers: a window.
      final sent = MediaQuery.sizeOf(context).width < wideListingLayout
          ? await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              useRootNavigator: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(context.brand.radiusMd * 2))),
              builder: (_) => _ReviewDialog(listing: listing, sheet: true),
            )
          : await showDialog<bool>(context: context, builder: (_) => _ReviewDialog(listing: listing));
      if (sent == true && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Thank you. Your review shows once it has been checked.')));
      }
    }

    return Column(key: const Key('reviews'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(reviews.isEmpty ? 'Reviews' : 'Reviews (${reviews.length})', style: text.titleLarge)),
        OutlinedButton.icon(
            key: const Key('write-review'), onPressed: write, icon: const Icon(Icons.rate_review_outlined), label: const Text('Write a review')),
      ]),
      SizedBox(height: b.spacing.md),
      if (average != null)
        Row(children: [
          Text(average.toStringAsFixed(1), style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(width: b.spacing.sm),
          stars(average, size: 22),
          SizedBox(width: b.spacing.sm),
          Flexible(child: Text('from ${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}', style: text.bodyMedium?.copyWith(color: b.textMuted))),
        ])
      else
        Text('No reviews yet. Lived here or viewed it? Be the first to say what it is like.', style: text.bodyMedium?.copyWith(color: b.textMuted)),
      for (final r in reviews.take(6))
        Padding(
          padding: EdgeInsets.only(top: b.spacing.md),
          child: Container(
            padding: EdgeInsets.all(b.spacing.md),
            decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(b.radiusMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                stars(r.rating),
                SizedBox(width: b.spacing.sm),
                if (r.afterViewing)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
                    decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
                    child: Text('After a viewing', style: text.labelSmall?.copyWith(color: scheme.primary)),
                  ),
              ]),
              if (r.comment != null) ...[SizedBox(height: b.spacing.sm), Text(r.comment!, style: text.bodyMedium)],
              SizedBox(height: b.spacing.sm),
              Text('${r.name ?? 'A visitor'} · ${months[r.createdAt.month - 1]} ${r.createdAt.year}', style: text.bodySmall?.copyWith(color: b.textMuted)),
            ]),
          ),
        ),
    ]);
  }
}

/// Stars, a comment and a first name; sent to be checked.
class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.listing, this.sheet = false});
  final ListingSummary listing;

  /// Laid out as a bottom sheet (phones) rather than a window.
  final bool sheet;

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  int _rating = 0;
  final _comment = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0) return setState(() => _error = 'Choose from 1 to 5 stars.');
    if (_comment.text.trim().length < 3) return setState(() => _error = 'Say a few words about the home.');
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(listingReviewsProvider).submit(listingId: widget.listing.id, rating: _rating, comment: _comment.text.trim(), name: _name.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on LeadException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.code == 'already-exists' ? 'You have already reviewed this home.' : 'That did not send. Please try again.';
        });
      }
    }
  }

  static const _words = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final form = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.listing.title, style: text.bodyMedium?.copyWith(color: b.textMuted)),
      SizedBox(height: b.spacing.lg),
      Text('Your rating', style: text.titleSmall),
      SizedBox(height: b.spacing.xs),
      Row(children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            key: Key('star-$i'),
            tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _rating = i),
            icon: Icon(_rating >= i ? Icons.star_rounded : Icons.star_outline_rounded, color: b.accent, size: 36),
          ),
        SizedBox(width: b.spacing.sm),
        Text(_words[_rating], style: text.titleSmall?.copyWith(color: b.textMuted)),
      ]),
      SizedBox(height: b.spacing.md),
      TextField(
        key: const Key('review-comment'),
        controller: _comment,
        minLines: 3,
        maxLines: 5,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Your review', alignLabelWithHint: true, hintText: 'Water, security, the neighbours, the landlord...'),
      ),
      SizedBox(height: b.spacing.sm),
      TextField(
        key: const Key('review-name'),
        controller: _name,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'First name (optional)', helperText: 'Only your first name is shown.'),
      ),
      if (_error != null) Padding(padding: EdgeInsets.only(top: b.spacing.sm), child: Text(_error!, style: TextStyle(color: scheme.error))),
      Padding(
        padding: EdgeInsets.only(top: b.spacing.sm),
        child: Row(children: [
          Icon(Icons.verified_user_outlined, size: 16, color: b.textMuted),
          SizedBox(width: b.spacing.xs),
          Expanded(child: Text('Reviews are checked before they show.', style: text.bodySmall?.copyWith(color: b.textMuted))),
        ]),
      ),
    ]);
    final send = FilledButton(
      key: const Key('send-review'),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: _sending ? null : _send,
      child: Text(_sending ? 'Sending…' : 'Send review'),
    );
    if (widget.sheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.sm, b.spacing.gutter, b.spacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Review this home', style: text.titleLarge)),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close)),
            ]),
            form,
            SizedBox(height: b.spacing.lg),
            send,
          ]),
        ),
      );
    }
    return AlertDialog(
      title: const Text('Review this home'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: form)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        send,
      ],
    );
  }
}

/// An icon for each feature or amenity the filters and the admin use;
/// anything else gets a tick.
IconData amenityIcon(String key) => switch (key.toLowerCase().replaceAll(' ', '-')) {
      // One outlined set, so the tiles look alike.
      'furnished' => Icons.chair_outlined,
      'parking' => Icons.local_parking_outlined,
      'security' => Icons.shield_outlined,
      'cctv' => Icons.videocam_outlined,
      'borehole' => Icons.water_outlined,
      'water' => Icons.water_drop_outlined,
      'wifi' || 'wi-fi' => Icons.wifi,
      'internet' || 'fibre' => Icons.router_outlined,
      'lift' || 'elevator' => Icons.elevator_outlined,
      'gym' => Icons.fitness_center_outlined,
      'swimming-pool' || 'pool' => Icons.pool_outlined,
      'garden' => Icons.park_outlined,
      'balcony' => Icons.balcony_outlined,
      'backup-generator' || 'generator' || 'electricity-backup' => Icons.electric_bolt_outlined,
      'pets' || 'pet-friendly' => Icons.pets_outlined,
      'playground' => Icons.toys_outlined,
      'servant-quarters' || 'dsq' => Icons.bedroom_child_outlined,
      'solar' || 'solar-water-heating' => Icons.solar_power_outlined,
      'air-conditioning' || 'ac' => Icons.ac_unit_outlined,
      'shops' => Icons.storefront_outlined,
      _ => Icons.check_circle_outline,
    };

/// The groups amenities are shown in, in order.
const amenityGroups = ['Features', 'Building', 'Security', 'Health and fitness', 'Utilities', 'Outdoors', 'Other'];

/// Which group an amenity belongs to.
String amenityGroup(String key) => switch (key.toLowerCase().replaceAll(' ', '-')) {
      'furnished' || 'balcony' || 'air-conditioning' || 'ac' || 'servant-quarters' || 'dsq' || 'pets' || 'pet-friendly' => 'Features',
      'parking' || 'lift' || 'elevator' || 'shops' => 'Building',
      'security' || 'cctv' => 'Security',
      'gym' || 'swimming-pool' || 'pool' => 'Health and fitness',
      'borehole' ||
      'water' ||
      'wifi' ||
      'wi-fi' ||
      'internet' ||
      'fibre' ||
      'backup-generator' ||
      'generator' ||
      'electricity-backup' ||
      'solar' ||
      'solar-water-heating' =>
        'Utilities',
      'garden' || 'playground' => 'Outdoors',
      _ => 'Other',
    };

/// Features and amenities as tiles with an icon, as on the big portals: the
/// first few, then "+ N more" which opens them all.
class _Amenities extends StatelessWidget {
  const _Amenities({required this.amenities, required this.wide});
  final List<String> amenities;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final shown = wide ? 5 : 3;
    final more = amenities.length - shown;
    // Six fit across the details column (775 wide), five then "+ N more".
    final tileWidth = wide ? 120.0 : 104.0;
    Widget tile(Widget child, {Color? color, VoidCallback? onTap, Key? key}) => SizedBox(
          width: tileWidth,
          height: tileWidth,
          child: Material(
            key: key,
            color: color ?? b.surfaceAlt,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(b.radiusSm),
              side: color == null ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(b.radiusSm),
              onTap: onTap,
              child: Padding(padding: EdgeInsets.all(b.spacing.sm), child: Center(child: child)),
            ),
          ),
        );
    Widget amenity(String a) => Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(amenityIcon(a), size: 26, color: scheme.onSurface),
          SizedBox(height: b.spacing.sm),
          Text(typeName(a), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
        ]);
    // Everything, grouped as the portals group it; full screen on phones.
    void showAll() {
      final groups = <String, List<String>>{};
      for (final a in amenities) {
        groups.putIfAbsent(amenityGroup(a), () => []).add(a);
      }
      final body = ListView(
        padding: EdgeInsets.fromLTRB(b.spacing.lg, 0, b.spacing.lg, b.spacing.xl),
        children: [
          for (final g in amenityGroups)
            if (groups[g] case final items?) ...[
              Padding(
                padding: EdgeInsets.only(top: b.spacing.lg, bottom: b.spacing.sm),
                child: Text(g.toUpperCase(), style: text.labelLarge?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
              ),
              Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [for (final a in items) tile(amenity(a))]),
            ],
        ],
      );
      Widget header(BuildContext context) => Padding(
            padding: EdgeInsets.fromLTRB(b.spacing.sm, b.spacing.sm, b.spacing.sm, 0),
            child: Row(children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: b.spacing.md),
                  child: Text('FEATURES & AMENITIES', style: text.titleSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                ),
              ),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          );
      showDialog<void>(
        context: context,
        builder: (context) => wide
            ? Dialog(
                key: const Key('all-amenities'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    header(context),
                    Flexible(child: body),
                  ]),
                ),
              )
            : Dialog.fullscreen(
                key: const Key('all-amenities'),
                child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header(context), Expanded(child: body)])),
              ),
      );
    }

    return Wrap(key: const Key('amenities'), spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
      for (final a in amenities.take(more > 0 ? shown : amenities.length)) tile(amenity(a)),
      if (more > 0)
        tile(
          Text('+ $more more\namenities', textAlign: TextAlign.center, style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          key: const Key('more-amenities'),
          color: scheme.surface,
          onTap: showAll,
        ),
    ]);
  }
}
