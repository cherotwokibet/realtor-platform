import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'paged_table.dart';
import 'providers.dart';

/// Heading, optional filters and a table, in a scrollable page.
class _TablePage extends StatelessWidget {
  const _TablePage({required this.title, this.subtitle, this.filters, required this.table});
  final String title;
  final String? subtitle;
  final Widget? filters;
  final Widget table;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: t.headlineSmall),
        if (subtitle != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: t.bodyMedium)),
        if (filters != null) Padding(padding: const EdgeInsets.only(top: 12), child: filters),
        const SizedBox(height: 12),
        Card(clipBehavior: Clip.antiAlias, child: table),
      ],
    );
  }
}

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});
  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  String? _stage;

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Leads',
      subtitle: who.isManager ? 'Every agent\'s leads, newest first.' : 'Your leads, newest first.',
      filters: FilterChips(
          values: leadStages, selected: _stage, labelOf: label, onSelected: (s) => setState(() => _stage = s)),
      table: PagedTable<LeadRow>(
        key: ValueKey(('leads', who.uid, _stage)),
        empty: 'No leads at this stage.',
        load: (after) => repo.leads(who, stage: _stage, after: after, limit: pageSize),
        columns: [
          TableColumn('Received', (r) => Text(shortDateTime(r.createdAt))),
          TableColumn('Name', (r) => Text(r.contactName ?? '—')),
          TableColumn('Phone', (r) => Text(r.contactPhone ?? '—')),
          TableColumn('Listing', (r) => Text(r.listingTitle)),
          TableColumn('Channel', (r) => Text(label(r.channel))),
          TableColumn('Stage', (r) => Text(label(r.stage))),
          if (who.isManager) TableColumn('Agent', (r) => Text(r.agentName)),
        ],
      ),
    );
  }
}

class ListingsScreen extends ConsumerStatefulWidget {
  const ListingsScreen({super.key});
  @override
  ConsumerState<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends ConsumerState<ListingsScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Listings',
      subtitle:
          who.isManager ? 'Every listing, most recently updated first.' : 'Your listings, most recently updated first.',
      filters: FilterChips(
        values: listingStatuses,
        selected: _status,
        labelOf: label,
        onSelected: (s) => setState(() => _status = s),
      ),
      table: PagedTable<StaffListingRow>(
        key: ValueKey(('listings', who.uid, _status)),
        empty: 'No listings with this status.',
        load: (after) => repo.listings(who, status: _status, after: after, limit: pageSize),
        columns: [
          TableColumn('Title', (r) => Text(r.title)),
          TableColumn('Area', (r) => Text(label(r.area))),
          TableColumn('Price', (r) => Text(formatKes(r.priceKES)), numeric: true),
          TableColumn('Status', (r) => Text(label(r.status))),
          TableColumn('Leads', (r) => Text('${r.leads}'), numeric: true),
          TableColumn('Calls', (r) => Text('${r.calls}'), numeric: true),
          TableColumn('WhatsApp', (r) => Text('${r.whatsapps}'), numeric: true),
          if (who.isManager) TableColumn('Agent', (r) => Text(r.agentName)),
          TableColumn('Updated', (r) => Text(shortDateTime(r.updatedAt))),
        ],
      ),
    );
  }
}

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Audit log',
      subtitle: 'Every staff action, written by the server with the change itself.',
      table: PagedTable<AuditRow>(
        key: ValueKey(('audit', who.uid)),
        load: (after) => repo.audit(who, after: after, limit: pageSize),
        columns: [
          TableColumn('When', (r) => Text(shortDateTime(r.at))),
          TableColumn('Who', (r) => Text('${r.actorName} (${label(r.actorRole.name)})')),
          TableColumn('Action', (r) => Text(label(r.action))),
          TableColumn('On', (r) => Text(r.target)),
          TableColumn('Change', (r) => Text([r.from, r.to].whereType<String>().map(label).join(' → '))),
          TableColumn('Reason', (r) => Text(r.reason ?? '')),
        ],
      ),
    );
  }
}
