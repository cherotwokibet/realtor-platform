import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'paged_table.dart';
import 'providers.dart';

/// Bookings and payments (managers): every M-Pesa payment (viewing fees,
/// deposits, featured-ad fees) with its outcome and receipt, filtered by
/// status, with this month's totals; a viewing fee opens its booking on the
/// Viewings page. Money is only ever moved by the Functions; this reads.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  String? _status;
  late final Future<List<PaymentRow>> _month = _loadMonth();

  /// This month's payments, for the totals (a month is a few hundred at most).
  Future<List<PaymentRow>> _loadMonth() async {
    final who = ref.read(staffProvider)!, repo = ref.read(adminRepositoryProvider);
    final now = DateTime.now(), start = DateTime(now.year, now.month);
    final out = <PaymentRow>[];
    String? after;
    do {
      final page = await repo.payments(who, after: after, limit: 100);
      out.addAll(page.rows.where((p) => !p.createdAt.isBefore(start)));
      if (page.rows.isEmpty || page.rows.last.createdAt.isBefore(start)) break;
      after = page.next;
    } while (after != null && out.length < 2000);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget stat(String key, String label, String value, String caption, IconData icon) => Container(
          key: Key(key),
          padding: const EdgeInsets.all(18),
          decoration:
              BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(b.radiusMd + 4), border: Border.all(color: scheme.outlineVariant)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: t.bodyMedium?.copyWith(color: b.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(caption, style: t.bodySmall?.copyWith(color: b.textMuted)),
              ]),
            ),
            Icon(icon, color: scheme.primary),
          ]),
        );
    Widget chip(String status) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: switch (status) { 'paid' => b.success.withValues(alpha: 0.12), 'pending' => b.primarySoft, _ => scheme.error.withValues(alpha: 0.12) },
            borderRadius: BorderRadius.circular(b.radiusSm),
          ),
          child: Text(label(status),
              style: t.labelMedium
                  ?.copyWith(color: switch (status) { 'paid' => b.success, 'pending' => scheme.primary, _ => scheme.error }, fontWeight: FontWeight.w700)),
        );

    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Bookings & payments', style: t.headlineSmall),
      const SizedBox(height: 4),
      Text('M-Pesa payments for viewings, deposits and featured ads. A viewing fee links to its booking.', style: t.bodyMedium?.copyWith(color: b.textMuted)),
      const SizedBox(height: 16),
      FutureBuilder<List<PaymentRow>>(
        future: _month,
        builder: (context, snap) {
          final m = snap.data ?? const <PaymentRow>[];
          final paid = m.where((p) => p.status == 'paid');
          final total = paid.fold(0, (a, p) => a + p.amountKES);
          return LayoutBuilder(builder: (context, box) {
            final across = box.maxWidth >= 1000 ? 4 : 2;
            final w = (box.maxWidth - 16 * (across - 1)) / across;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(width: w, child: stat('pay-total', 'Collected this month', formatKes(total), '${paid.length} payments', Icons.payments_outlined)),
              SizedBox(
                  width: w,
                  child: stat('pay-viewings', 'Viewing fees', '${paid.where((p) => p.purpose == 'viewing-fee').length}', 'paid this month',
                      Icons.event_available_outlined)),
              SizedBox(
                  width: w,
                  child: stat(
                      'pay-pending', 'Waiting', '${m.where((p) => p.status == 'pending').length}', 'asked on the phone, not yet paid', Icons.hourglass_top)),
              SizedBox(
                  width: w,
                  child: stat('pay-failed', 'Did not go through', '${m.where((p) => p.status == 'failed' || p.status == 'cancelled').length}',
                      'failed or cancelled', Icons.error_outline)),
            ]);
          });
        },
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: [
        for (final s in <String?>[null, ...paymentStatuses])
          ChoiceChip(
            key: Key('pay-status-${s ?? 'all'}'),
            label: Text(s == null ? 'All' : label(s)),
            selected: _status == s,
            showCheckmark: false,
            onSelected: (_) => setState(() => _status = s),
          ),
      ]),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: PagedTable<PaymentRow>(
          key: ValueKey(('payments', _status)),
          load: (after) => repo.payments(who, status: _status, after: after, limit: pageSize),
          empty: 'No payments yet.',
          columns: [
            TableColumn('When', (p) => Text(shortDateTime(p.createdAt))),
            TableColumn('For', (p) => Text(label(p.purpose))),
            TableColumn('Amount', (p) => Text(formatKes(p.amountKES)), numeric: true),
            TableColumn('Status', (p) => Tooltip(message: p.reason ?? '', child: chip(p.status))),
            TableColumn('Receipt', (p) => SelectableText(p.receipt ?? '—')),
            TableColumn('Phone', (p) => Text(p.phone)),
            TableColumn(
              'Listing / booking',
              (p) => p.viewingId != null
                  ? TextButton(onPressed: () => context.go('/viewings'), child: Text(p.listingTitle ?? 'Viewing'))
                  : Text(p.listingTitle ?? p.listingId ?? '—'),
            ),
          ],
        ),
      ),
    ]);
  }
}
