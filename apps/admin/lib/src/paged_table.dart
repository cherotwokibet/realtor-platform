import 'package:flutter/material.dart';
import 'package:realtor_core/realtor_core.dart';

/// A column: its heading and how a row fills it.
class TableColumn<T> {
  const TableColumn(this.label, this.cell, {this.numeric = false});
  final String label;
  final Widget Function(T row) cell;
  final bool numeric;
}

/// A data table that loads one page at a time from the server and pages
/// with the cursor each page returns. Give it a new [key] when a filter
/// changes, so it starts again from the first page.
class PagedTable<T> extends StatefulWidget {
  const PagedTable({super.key, required this.columns, required this.load, this.empty = 'Nothing here yet.'});
  final List<TableColumn<T>> columns;
  final Future<RowPage<T>> Function(String? after) load;
  final String empty;

  @override
  State<PagedTable<T>> createState() => _PagedTableState<T>();
}

class _PagedTableState<T> extends State<PagedTable<T>> {
  /// The cursor each page was loaded with; the last one is on screen.
  final _cursors = <String?>[null];
  late Future<RowPage<T>> _page = widget.load(null);

  void _go(String? cursor, {required bool back}) => setState(() {
        if (back) {
          _cursors.removeLast();
        } else {
          _cursors.add(cursor);
        }
        _page = widget.load(_cursors.last);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<RowPage<T>>(
      future: _page,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text("Couldn't load this page: ${snap.error}", style: TextStyle(color: theme.colorScheme.error)),
          );
        }
        final page = snap.data;
        if (page == null)
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (page.rows.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text(widget.empty))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [for (final c in widget.columns) DataColumn(label: Text(c.label), numeric: c.numeric)],
                  rows: [
                    for (final r in page.rows) DataRow(cells: [for (final c in widget.columns) DataCell(c.cell(r))]),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Page ${_cursors.length}', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Previous page',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _cursors.length > 1 ? () => _go(null, back: true) : null,
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: page.next == null ? null : () => _go(page.next, back: false),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "All" plus one chip per value; [onSelected] gets null for "All".
class FilterChips extends StatelessWidget {
  const FilterChips(
      {super.key, required this.values, required this.selected, required this.onSelected, required this.labelOf});
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final String Function(String) labelOf;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(label: const Text('All'), selected: selected == null, onSelected: (_) => onSelected(null)),
          for (final v in values)
            ChoiceChip(label: Text(labelOf(v)), selected: selected == v, onSelected: (_) => onSelected(v)),
        ],
      );
}
