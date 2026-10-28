/// CSV bulk import of listings (P5-s02): a spreadsheet saved as CSV becomes
/// rows for the `importListings` Function. Checked here only for what makes
/// a row unreadable (missing column, a number that is not one); the
/// Function validates everything else exactly as a single submission.
library;

import 'listing_filters.dart';

/// Columns, in the order a template sheet lists them. `amenities` is
/// separated by ";" inside its cell.
const listingCsvColumns = [
  'title',
  'purpose',
  'type',
  'beds',
  'baths',
  'priceKES',
  'depositMonths',
  'serviceChargeKES',
  'lat',
  'lng',
  'area',
  'estate',
  'amenities',
  'agentId',
];

const _required = {'title', 'purpose', 'type', 'beds', 'baths', 'priceKES', 'lat', 'lng', 'area', 'agentId'};
const _ints = {'beds', 'baths', 'priceKES', 'depositMonths', 'serviceChargeKES'};
const _decimals = {'lat', 'lng'};
final _moneyNoise = RegExp(r'kes|ksh|[\s,]', caseSensitive: false);

class ListingCsv {
  const ListingCsv({required this.rows, required this.problems});

  /// One map per good data row, keyed by column, ready for `importListings`.
  final List<({int line, Map<String, Object?> row})> rows;

  /// What is wrong, by line of the file (the header is line 1).
  final List<({int line, String problem})> problems;

  bool get ok => problems.isEmpty;

  static ListingCsv parse(String text) {
    final table = parseCsv(text);
    if (table.isEmpty) return const ListingCsv(rows: [], problems: [(line: 1, problem: 'the file is empty')]);
    // Header names match regardless of case and spaces ("Price KES" = priceKES).
    String key(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final known = {for (final c in listingCsvColumns) key(c): c};
    final header = [for (final h in table.first) known[key(h)]];
    final missing = _required.where((c) => !header.contains(c)).toList();
    if (missing.isNotEmpty) {
      return ListingCsv(rows: const [], problems: [(line: 1, problem: 'missing columns: ${missing.join(', ')}')]);
    }

    final rows = <({int line, Map<String, Object?> row})>[];
    final problems = <({int line, String problem})>[];
    for (var i = 1; i < table.length; i++) {
      final cells = table[i];
      if (cells.every((c) => c.trim().isEmpty)) continue; // blank line
      final line = i + 1;
      final row = <String, Object?>{};
      final errors = <String>[];
      for (var c = 0; c < header.length; c++) {
        final col = header[c];
        if (col == null) continue; // a column we do not import
        final raw = c < cells.length ? cells[c].trim() : '';
        if (raw.isEmpty) {
          if (_required.contains(col)) errors.add('$col is empty');
          continue;
        }
        if (_ints.contains(col)) {
          // "65,000", "KES 65000" and "65 000" are all 65000.
          final n = int.tryParse(raw.replaceAll(_moneyNoise, ''));
          n == null ? errors.add('$col "$raw" is not a whole number') : row[col] = n;
        } else if (_decimals.contains(col)) {
          final n = double.tryParse(raw);
          n == null ? errors.add('$col "$raw" is not a number') : row[col] = n;
        } else if (col == 'amenities') {
          row[col] = [for (final a in raw.split(';')) if (a.trim().isNotEmpty) a.trim()];
        } else if (col == 'purpose') {
          final p = raw.toLowerCase().replaceAll(' ', '-');
          Purpose.values.any((v) => v.value == p) ? row[col] = p : errors.add('purpose "$raw" is not rent, sale or short-stay');
        } else if (col == 'type') {
          final t = raw.toLowerCase().replaceAll(' ', '-');
          listingTypeSlugs.containsKey(t) ? row[col] = t : errors.add('type "$raw" is not one of ${listingTypeSlugs.keys.join(', ')}');
        } else {
          row[col] = raw;
        }
      }
      if (errors.isEmpty) {
        rows.add((line: line, row: row));
      } else {
        problems.add((line: line, problem: errors.join('; ')));
      }
    }
    if (rows.isEmpty && problems.isEmpty) problems.add((line: 2, problem: 'no listings under the header'));
    return ListingCsv(rows: rows, problems: problems);
  }
}

/// RFC 4180 CSV: commas, double-quoted fields with "" for a quote, quoted
/// line breaks, CRLF or LF. A leading byte-order mark (Excel) is ignored.
List<List<String>> parseCsv(String text) {
  final s = text.startsWith('﻿') ? text.substring(1) : text;
  final out = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      out.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    out.add(row);
  }
  return out;
}
