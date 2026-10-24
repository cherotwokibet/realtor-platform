import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'providers.dart';

/// First screen: proves brand, features and Kenyan property types all come from data.
/// Real listings arrive with the P2 data layer.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum Purpose { rent, buy }

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Purpose _purpose = Purpose.rent;

  static const _types = ['Bedsitter', 'Single room', 'Apartment', 'Maisonette', 'Townhouse', 'Hostel'];

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final f = tenant.features;
    final purposes = [if (f.rent) Purpose.rent, if (f.sale) Purpose.buy];
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
              segments: const [
                ButtonSegment(value: Purpose.rent, label: Text('Rent')),
                ButtonSegment(value: Purpose.buy, label: Text('Buy')),
              ],
              selected: {_purpose},
              onSelectionChanged: (s) => setState(() => _purpose = s.first),
            ),
          SizedBox(height: b.spacing.md),
          const TextField(
            decoration: InputDecoration(
              hintText: 'Area or estate, e.g. Kilimani, Ruaka',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          SizedBox(height: b.spacing.md),
          Wrap(
            spacing: b.spacing.sm,
            runSpacing: b.spacing.sm,
            children: [for (final t in _types) FilterChip(label: Text(t), onSelected: (_) {})],
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
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: tenant.hasContactNumbers
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
