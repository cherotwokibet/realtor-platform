import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'search/purpose.dart';
import 'search/recent_searches.dart';
import 'search/results_screen.dart';

/// First screen: search, property types and the newest live homes, with brand
/// and features from the tenant's data.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Purpose _purpose = Purpose.rent;

  static const _types = ['bedsitter', 'single-room', 'apartment', 'maisonette', 'townhouse', 'hostel'];

  void _search({String? q, String? type}) {
    // Plain search: an exact area name ("Ruaka") is that area, so results
    // and alerts match the area rather than the words.
    final typed = q?.trim().toLowerCase();
    final names = ref.read(areaNamesProvider).value ?? const <String, String>{};
    final area = typed == null || typed.isEmpty
        ? null
        : names.entries.where((e) => e.value.toLowerCase() == typed || e.key == typed.replaceAll(' ', '-')).map((e) => e.key).firstOrNull;
    context.push(ListingFilters(
      purpose: _purpose,
      q: area == null ? q : null,
      types: [if (type != null) type],
      areas: [if (area != null) area],
    ).toUri().toString());
  }

  /// Conversational search (P7-s01): "2br Kilimani under 60k with parking"
  /// becomes filters; the results screen shows each one as a chip to remove.
  void _ask(String text) {
    final features = ref.read(tenantProvider).features;
    final parsed = parseSearch(
      text,
      purpose: _purpose,
      areas: ref.read(areaNamesProvider).value ?? const {},
      allowed: {for (final p in Purpose.values) if (features.isOn(p.feature)) p},
    );
    context.push(parsed.filters.toUri().toString());
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantProvider);
    // Area names for typed searches, loaded before anyone presses search.
    ref.watch(areaNamesProvider);
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final purposes = [for (final p in Purpose.values) if (tenant.features.isOn(p.feature)) p];
    if (!purposes.contains(_purpose) && purposes.isNotEmpty) _purpose = purposes.first;
    final whatsapp = tenant.whatsappLink('Hello ${tenant.name}, I am looking for a home.');

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(b.logoAsset, height: 36, semanticLabel: tenant.name),
        centerTitle: false,
      ),
      body: ListView(
        padding: EdgeInsets.all(b.spacing.gutter),
        children: [
          Text(tenant.tagline ?? tenant.name, style: text.headlineMedium),
          SizedBox(height: b.spacing.lg),
          if (purposes.length > 1)
            SegmentedButton<Purpose>(
              segments: [for (final p in purposes) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_purpose},
              onSelectionChanged: (s) => setState(() => _purpose = s.first),
            ),
          SizedBox(height: b.spacing.md),
          FeatureGate(
            feature: Feature.aiSearch,
            orElse: TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => _search(q: q),
              decoration: const InputDecoration(
                hintText: 'Area or estate, e.g. Kilimani, Ruaka',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            child: TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: _ask,
              decoration: const InputDecoration(
                hintText: 'Try "2br Kilimani under 60k with parking"',
                prefixIcon: Icon(Icons.auto_awesome),
              ),
            ),
          ),
          SizedBox(height: b.spacing.md),
          Wrap(
            spacing: b.spacing.sm,
            runSpacing: b.spacing.sm,
            children: [for (final t in _types) ActionChip(label: Text(typeName(t)), onPressed: () => _search(type: t))],
          ),
          const RecentSearches(),
          FeatureGate(
            feature: Feature.ads,
            child: Padding(
              padding: EdgeInsets.only(top: b.spacing.xl),
              child: Card(
                color: b.primarySoft,
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text('Featured', style: text.labelSmall),
                  subtitle: Text('Promoted listings appear here', style: text.bodyMedium),
                ),
              ),
            ),
          ),
          SizedBox(height: b.spacing.xl),
          _Newest(purpose: _purpose, onSeeAll: () => _search()),
        ],
      ),
      // In-app chat lives in its own section when on; otherwise WhatsApp handoff.
      bottomNavigationBar: !tenant.features.chat && whatsapp != null
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.all(b.spacing.md),
                child: FilledButton.icon(
                  onPressed: () => ref.read(urlOpenerProvider)(whatsapp),
                  icon: const Icon(Icons.chat),
                  label: const Text('Enquire on WhatsApp'),
                ),
              ),
            )
          : null,
    );
  }
}

/// The newest few homes for [purpose]; nothing at all while loading, on an
/// error or when there are none, so the search above stays the focus.
class _Newest extends ConsumerWidget {
  const _Newest({required this.purpose, required this.onSeeAll});
  final Purpose purpose;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(searchResultsProvider(ListingFilters(purpose: purpose))).value?.hits ?? const [];
    if (hits.isEmpty) return const SizedBox.shrink();
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Newest ${purpose.heading}', style: Theme.of(context).textTheme.titleLarge)),
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ]),
        SizedBox(height: b.spacing.sm),
        for (final l in hits.take(3)) ...[ListingCard(listing: l), SizedBox(height: b.spacing.md)],
      ],
    );
  }
}
