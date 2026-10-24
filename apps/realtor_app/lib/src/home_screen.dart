import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'providers.dart';

/// First screen: proves brand, features and Kenyan property types all come from data.
/// Real listings arrive with the P2 data layer.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Search purposes, each behind its feature switch.
enum Purpose {
  rent('Rent', Feature.rent),
  buy('Buy', Feature.sale),
  shortStay('Short stay', Feature.shortStay);

  const Purpose(this.label, this.feature);
  final String label;
  final Feature feature;
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Purpose _purpose = Purpose.rent;

  static const _types = ['Bedsitter', 'Single room', 'Apartment', 'Maisonette', 'Townhouse', 'Hostel'];

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final purposes = [for (final p in Purpose.values) if (tenant.features.isOn(p.feature)) p];
    if (!purposes.contains(_purpose) && purposes.isNotEmpty) _purpose = purposes.first;

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
            orElse: const TextField(
              decoration: InputDecoration(
                hintText: 'Area or estate, e.g. Kilimani, Ruaka',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: 'Try "2br Kilimani under 60k with parking"',
                prefixIcon: Icon(Icons.auto_awesome),
              ),
            ),
          ),
          SizedBox(height: b.spacing.md),
          Wrap(
            spacing: b.spacing.sm,
            runSpacing: b.spacing.sm,
            children: [for (final t in _types) FilterChip(label: Text(t), onSelected: (_) {})],
          ),
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
          Text('Sample listing', style: text.titleLarge),
          SizedBox(height: b.spacing.sm),
          Card(
            child: Padding(
              padding: EdgeInsets.all(b.spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VerifiedBadge(verifiedAt: DateTime.now()),
                  SizedBox(height: b.spacing.sm),
                  Text('2 bedroom apartment, Kilimani', style: text.titleMedium),
                  SizedBox(height: b.spacing.xs),
                  const PriceText(65000, period: 'month'),
                  SizedBox(height: b.spacing.xs),
                  Text('Deposit 2 months · Water and Wi-Fi included', style: text.bodySmall),
                  FeatureGate(
                    feature: Feature.mpesa,
                    child: Padding(
                      padding: EdgeInsets.only(top: b.spacing.sm),
                      child: Text('Book a viewing · pay with M-Pesa', style: text.labelLarge),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // In-app chat lives in its own section when on; otherwise WhatsApp handoff.
      bottomNavigationBar: !tenant.features.chat && tenant.hasContactNumbers
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.all(b.spacing.md),
                child: FilledButton.icon(
                  onPressed: () {}, // url_launcher with tenant.whatsappLink(...) in P4
                  icon: const Icon(Icons.chat),
                  label: const Text('Enquire on WhatsApp'),
                ),
              ),
            )
          : null,
    );
  }
}
