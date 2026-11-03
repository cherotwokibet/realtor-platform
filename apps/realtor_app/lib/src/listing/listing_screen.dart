import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
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

class _ListingView extends ConsumerWidget {
  const _ListingView({required this.detail});
  final ListingDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    final l = detail.summary;
    final facts = [
      if (l.beds > 0) '${l.beds} bed' else typeName(l.type),
      if (l.baths > 0) '${l.baths} bath',
      [if (detail.estate != null) detail.estate!, areaName(l.area)].join(', '),
    ].join(' · ');
    final phone = detail.agent?.phone ?? (tenant.hasContactNumbers ? tenant.phone : null);
    final whatsapp = detail.agent?.whatsapp ?? (tenant.hasContactNumbers ? tenant.whatsapp : null);

    Future<void> contact(String channel, Uri uri) async {
      // Counting the tap (D13) must never stop the call or chat.
      ref.read(leadRepositoryProvider).logTap(listingId: l.id, channel: channel).ignore();
      if (!await ref.read(urlOpenerProvider)(uri) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app on this phone can open that.')));
      }
    }

    return Scaffold(
      appBar: AppBar(leading: const AppBack(), title: Text(l.title, overflow: TextOverflow.ellipsis), actions: [FavouriteButton(listing: l)]),
      body: LayoutBuilder(builder: (context, box) {
        final photos = _Photos(key: const ValueKey('listing-photos'), urls: detail.photos, title: l.title);
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (l.verified) ...[const VerifiedBadge(), SizedBox(height: b.spacing.sm)],
            Text(l.title, style: text.headlineSmall),
            SizedBox(height: b.spacing.xs),
            PriceText(l.priceKES, period: l.purpose.period),
            SizedBox(height: b.spacing.xs),
            Text(facts, style: text.bodyMedium?.copyWith(color: b.textMuted)),
            if ((detail.viewingFeeKES ?? 0) > 0 && tenant.features.isOn(Feature.mpesa)) ...[
              SizedBox(height: b.spacing.xs),
              Text('Viewing fee: ${formatKes(detail.viewingFeeKES!)}, paid by M-Pesa after you book', style: text.bodyMedium),
            ],
            if (detail.depositMonths != null) ...[
              SizedBox(height: b.spacing.xs),
              Text('Deposit: ${detail.depositMonths} month${detail.depositMonths == 1 ? '' : 's'}', style: text.bodyMedium),
            ],
            if (detail.description.trim().isNotEmpty) ...[
              SizedBox(height: b.spacing.md),
              Text(detail.description.trim(), style: text.bodyMedium),
            ],
            if (l.amenities.isNotEmpty) ...[
              SizedBox(height: b.spacing.md),
              Wrap(
                spacing: b.spacing.sm,
                runSpacing: b.spacing.sm,
                children: [for (final a in l.amenities) Chip(label: Text(typeName(a)))],
              ),
            ],
            if (detail.agent != null) ...[
              SizedBox(height: b.spacing.lg),
              Text('Listed by ${detail.agent!.name}', style: text.bodyMedium),
            ],
            SizedBox(height: b.spacing.lg),
            Wrap(
              spacing: b.spacing.sm,
              runSpacing: b.spacing.sm,
              children: [
                if (whatsapp != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('WhatsApp'),
                    onPressed: () => contact(
                      'whatsapp',
                      Uri.https('wa.me', '/${whatsapp.replaceAll('+', '')}', {
                        'text': 'Hi, I saw "${l.title}" (https://${tenant.shareDomain}/listing/${l.slug}). Is it still available?',
                      }),
                    ),
                  ),
                if (phone != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call'),
                    onPressed: () => contact('call', Uri(scheme: 'tel', path: phone)),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Enquire'),
                  onPressed: () => showEnquirySheet(context, listing: l),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Book a viewing'),
                  onPressed: () => showViewingSheet(context, listing: l),
                ),
              ],
            ),
            _Similar(listing: l),
          ],
        );
        // Wide screens (web, tablets): photos beside the details, at the
        // same width as the rest of the app, so the page does not open on
        // a full-window photo with everything else below the fold.
        if (box.maxWidth >= wideListingLayout) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: ListView(
                padding: EdgeInsets.all(b.spacing.gutter).copyWith(bottom: b.spacing.xxl),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: ClipRRect(borderRadius: BorderRadius.circular(b.radiusMd), child: photos)),
                      SizedBox(width: b.spacing.xl),
                      Expanded(flex: 2, child: details),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.only(bottom: b.spacing.xxl),
          children: [photos, Padding(padding: EdgeInsets.all(b.spacing.gutter), child: details)],
        );
      }),
    );
  }
}

/// From this width the listing shows photos and details side by side.
const wideListingLayout = 900.0;

/// Up to three live homes like this one (P7-s04), from the same area and
/// the newest of the same purpose; nothing while loading or when none are close.
class _Similar extends ConsumerStatefulWidget {
  const _Similar({required this.listing});
  final ListingSummary listing;

  @override
  ConsumerState<_Similar> createState() => _SimilarState();
}

class _SimilarState extends ConsumerState<_Similar> {
  /// The listing the section was last counted as shown for.
  String? _counted;

  /// Click-through counts (P7-s04) are best effort: a failed count never
  /// gets in the way of the page.
  void _log(String event) => ref.read(leadRepositoryProvider).logRecommendation(listingId: widget.listing.id, event: event).catchError((Object _) {});

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final inArea = ref.watch(liveListingsProvider((area: listing.area, agent: null))).value ?? const [];
    final newest = ref.watch(searchResultsProvider(ListingFilters(purpose: listing.purpose))).value?.hits ?? const [];
    final similar = similarListings(listing, [...inArea, ...newest], similarKey);
    if (similar.isEmpty) return const SizedBox.shrink();
    if (_counted != listing.id) {
      _counted = listing.id;
      _log('shown');
    }
    final b = context.brand;
    return Padding(
      padding: EdgeInsets.only(top: b.spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Similar homes', style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: b.spacing.sm),
          for (final s in similar) ...[ListingCard(listing: s, onOpen: () => _log('opened')), SizedBox(height: b.spacing.md)],
        ],
      ),
    );
  }
}

/// Swipeable photos, or a quiet placeholder until the listing has some.
class _Photos extends StatefulWidget {
  const _Photos({super.key, required this.urls, required this.title});
  final List<String> urls;
  final String title;

  @override
  State<_Photos> createState() => _PhotosState();
}

/// Swipe on a phone; on the web also drag with the mouse, use the arrows on
/// the photo or the keyboard's left/right keys. "2 / 8" says how many there are.
class _PhotosState extends State<_Photos> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= widget.urls.length) return;
    _pages.animateToPage(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final urls = widget.urls;
    if (urls.isEmpty) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: b.surfaceAlt,
          child: Center(child: Icon(Icons.home_work_outlined, size: 64, color: b.textMuted, semanticLabel: 'No photos yet')),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    Widget arrow(IconData icon, String label, int to) => IconButton.filledTonal(
          key: Key(label),
          tooltip: label,
          onPressed: () => _go(to),
          icon: Icon(icon),
        );
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_index - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_index + 1),
        },
        child: Focus(
          child: Stack(fit: StackFit.expand, children: [
            ScrollConfiguration(
              // Flutter web leaves mouse dragging off for page views; turn it on.
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final (i, u) in urls.indexed)
                    Image.network(
                      u,
                      fit: BoxFit.cover,
                      semanticLabel: '${widget.title}, photo ${i + 1}',
                      errorBuilder: (context, error, stack) => ColoredBox(color: b.surfaceAlt),
                    ),
                ],
              ),
            ),
            if (urls.length > 1) ...[
              if (_index > 0)
                Positioned(left: b.spacing.sm, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left, 'Previous photo', _index - 1))),
              if (_index < urls.length - 1)
                Positioned(right: b.spacing.sm, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right, 'Next photo', _index + 1))),
              Positioned(
                right: b.spacing.sm,
                bottom: b.spacing.sm,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: scheme.inverseSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(b.radiusSm)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
                    child: Text('${_index + 1} / ${urls.length}',
                        key: const Key('photo-count'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onInverseSurface)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
