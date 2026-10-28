import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'providers.dart';

/// Saves text as a file in the browser; the web build overrides it.
abstract interface class FileSaver {
  void save(String fileName, String text, {String type = 'text/csv'});
}

/// Outside a browser: remembers what would have been saved (tests).
class MemoryFileSaver implements FileSaver {
  final saved = <(String, String)>[];
  @override
  void save(String fileName, String text, {String type = 'text/csv'}) => saved.add((fileName, text));
}

final fileSaverProvider = Provider<FileSaver>((ref) => MemoryFileSaver());

/// Monthly report (P5-s08), owners and managers: leads by stage and channel,
/// viewings by status, each agent's numbers and the busiest listings.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _months = reportMonths(DateTime.now());
  late String _month = _months.first;
  late Future<MonthlyReport> _report = _load();

  Future<MonthlyReport> _load() => ref.read(adminActionsProvider).monthlyReport(ref.read(staffProvider)!, _month);

  static String _monthLabel(String m) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final [y, mo] = m.split('-');
    return '${names[int.parse(mo) - 1]} $y';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Reports', style: t.headlineSmall),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('One month at a time, Nairobi time. Counts only; no client details.', style: t.bodyMedium),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: _month,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), isDense: true),
            items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(_monthLabel(m)))],
            onChanged: (m) => setState(() {
              _month = m!;
              _report = _load();
            }),
          ),
        ),
        FutureBuilder<MonthlyReport>(
          future: _report,
          builder: (context, snap) => OutlinedButton.icon(
            onPressed: snap.data == null
                ? null
                : () => ref.read(fileSaverProvider).save('report-${snap.data!.month}.csv', snap.data!.toCsv()),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download CSV'),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      FutureBuilder<MonthlyReport>(
        future: _report,
        builder: (context, snap) {
          if (snap.hasError) {
            return Text("Couldn't load the report: ${snap.error}", style: TextStyle(color: Theme.of(context).colorScheme.error));
          }
          final r = snap.data;
          if (r == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          return _ReportBody(report: r);
        },
      ),
    ]);
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});
  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final t = Theme.of(context).textTheme;
    Widget card(String title, Widget child) => Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.titleMedium), const SizedBox(height: 8), child]),
          ),
        );
    Widget counts(Map<String, int> m, List<String> order) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in [...order.where(m.containsKey), ...m.keys.where((k) => !order.contains(k))]) Chip(label: Text('${label(k)}: ${m[k]}')),
          if (m.isEmpty) const Text('None.'),
        ]);
    Widget table(List<String> cols, List<List<String>> rows, {Set<int> numeric = const {}}) => rows.isEmpty
        ? const Text('None this month.')
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [for (final (i, c) in cols.indexed) DataColumn(label: Text(c), numeric: numeric.contains(i))],
              rows: [for (final row in rows) DataRow(cells: [for (final c in row) DataCell(Text(c))])],
            ),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card('${r.leads} leads, ${r.viewings} viewings', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Leads by stage reached', style: t.labelLarge),
        const SizedBox(height: 4),
        counts(r.leadsByStage, MonthlyReport.funnel),
        const SizedBox(height: 12),
        Text('Leads by channel', style: t.labelLarge),
        const SizedBox(height: 4),
        counts(r.leadsByChannel, const ['form', 'viewing', 'call', 'whatsapp']),
        const SizedBox(height: 12),
        Text('Viewings', style: t.labelLarge),
        const SizedBox(height: 4),
        counts(r.viewingsByStatus, viewingStatuses),
      ])),
      card(
        'Agents',
        table(
          const ['Agent', 'Leads', 'Won', 'Viewings done', 'No-shows', 'Typical reply'],
          [
            for (final a in r.agents)
              [a.name, '${a.leads}', '${a.won}', '${a.viewingsDone}', '${a.noShows}', a.replyMins == null ? '—' : minutesLabel(a.replyMins!)],
          ],
          numeric: const {1, 2, 3, 4},
        ),
      ),
      card(
        'Listings with the most leads (all time)',
        table(
          const ['Listing', 'Leads', 'Calls', 'WhatsApp'],
          [for (final l in r.topListings) [l.title, '${l.leads}', '${l.calls}', '${l.whatsapps}']],
          numeric: const {1, 2, 3},
        ),
      ),
    ]);
  }
}
