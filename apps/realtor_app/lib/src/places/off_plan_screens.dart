import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import '../search/purpose.dart';
import '../nav.dart';

/// `/off-plan` (P5-s06): published off-plan projects, cheapest first. Only
/// routed when the tenant has the `offPlan` switch on.
class OffPlanScreen extends ConsumerWidget {
  const OffPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Off-plan')),
      body: ref.watch(projectsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(child: Text("Couldn't load the projects. Please try again.", style: text.bodyMedium)),
            data: (projects) => projects.isEmpty
                ? Center(child: Text('No off-plan projects right now.', style: text.bodyMedium))
                : ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
                    Text('Buy before it is built', style: text.headlineSmall),
                    SizedBox(height: b.spacing.xs),
                    Text('Homes sold off-plan, paid in stages until handover.', style: text.bodySmall?.copyWith(color: b.textMuted)),
                    SizedBox(height: b.spacing.lg),
                    for (final p in projects) ...[
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => context.push('/off-plan/${p.slug}'),
                          child: Padding(
                            padding: EdgeInsets.all(b.spacing.lg),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: text.titleMedium),
                              SizedBox(height: b.spacing.xs),
                              Text('From ${formatKes(p.fromKES)}', style: text.titleSmall),
                              SizedBox(height: b.spacing.xs),
                              Text('${areaName(p.area)} · ready ${p.handoverLabel} · by ${p.developer}', style: text.bodySmall),
                            ]),
                          ),
                        ),
                      ),
                      SizedBox(height: b.spacing.md),
                    ],
                  ]),
          ),
    );
  }
}

/// `/off-plan/<slug>`: units with from-prices, the payment plan, handover
/// and a WhatsApp question to the realtor.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    Widget missing() => Scaffold(
        appBar: AppBar(leading: const AppBack()), body: Center(child: Text('This project is not here any more.', style: text.bodyLarge)));
    return ref.watch(projectProvider(slug)).when(
          loading: () => Scaffold(appBar: AppBar(leading: const AppBack()), body: const Center(child: CircularProgressIndicator())),
          error: (_, __) => missing(),
          data: (p) {
            if (p == null) return missing();
            final wa = tenant.whatsappLink('Hi ${tenant.name}, I am interested in ${p.name}.');
            return Scaffold(
              appBar: AppBar(leading: const AppBack(), title: Text(p.name, overflow: TextOverflow.ellipsis)),
              body: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
                Text(p.name, style: text.headlineSmall),
                SizedBox(height: b.spacing.xs),
                Text('By ${p.developer} · ${areaName(p.area)} · ready ${p.handoverLabel}',
                    style: text.bodySmall?.copyWith(color: b.textMuted)),
                SizedBox(height: b.spacing.sm),
                Text('From ${formatKes(p.fromKES)}', style: text.titleMedium),
                if (p.summary.isNotEmpty) ...[SizedBox(height: b.spacing.md), Text(p.summary, style: text.bodyMedium)],
                SizedBox(height: b.spacing.lg),
                Text('Units', style: text.titleSmall),
                for (final u in p.units)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(u.label),
                    subtitle: u.sizeSqm == null ? null : Text('${u.sizeSqm} m²'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatKes(u.fromKES), style: text.titleSmall),
                      Text(u.available == 0 ? 'Sold out' : '${u.available} left', style: text.bodySmall),
                    ]),
                  ),
                SizedBox(height: b.spacing.md),
                Text('Payment plan', style: text.titleSmall),
                SizedBox(height: b.spacing.xs),
                for (final (i, s) in p.paymentPlan.indexed)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: b.spacing.xs),
                    child: Row(children: [
                      Expanded(child: Text('${i + 1}. ${s.stage}', style: text.bodyMedium)),
                      Text('${s.percent}%', style: text.titleSmall),
                    ]),
                  ),
                SizedBox(height: b.spacing.md),
                Text("Prices and dates are the developer's and can change; ask for the sale agreement before paying.",
                    style: text.bodySmall?.copyWith(color: b.textMuted)),
                if (wa != null) ...[
                  SizedBox(height: b.spacing.lg),
                  FilledButton.icon(
                    onPressed: () => ref.read(urlOpenerProvider)(wa),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Ask on WhatsApp'),
                  ),
                ],
              ]),
            );
          },
        );
  }
}
