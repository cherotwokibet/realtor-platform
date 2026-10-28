/// The `monthlyReport` Function's answer (P5-s08), and its CSV for a
/// spreadsheet. Counts only: no client's name or number is ever in it.
library;

typedef ReportAgentRow = ({String agentId, String name, int leads, int won, int viewingsDone, int noShows, int? replyMins});
typedef ReportListingRow = ({String listingId, String title, String agentId, int leads, int calls, int whatsapps});

class MonthlyReport {
  const MonthlyReport({
    required this.month,
    required this.leads,
    required this.leadsByChannel,
    required this.leadsByStage,
    required this.viewings,
    required this.viewingsByStatus,
    required this.agents,
    required this.topListings,
  });

  /// `YYYY-MM`, Nairobi time.
  final String month;
  final int leads, viewings;
  final Map<String, int> leadsByChannel, leadsByStage, viewingsByStatus;
  final List<ReportAgentRow> agents;

  /// Most leads so far (all time), at most 10.
  final List<ReportListingRow> topListings;

  factory MonthlyReport.fromJson(Map<Object?, Object?> j) {
    Map<String, int> counts(Object? m) => {for (final e in ((m as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
    int n(Map<Object?, Object?> m, String k) => (m[k] as num?)?.toInt() ?? 0;
    final leads = j['leads']! as Map, viewings = j['viewings']! as Map;
    return MonthlyReport(
      month: j['month']! as String,
      leads: n(leads, 'total'),
      leadsByChannel: counts(leads['byChannel']),
      leadsByStage: counts(leads['byStage']),
      viewings: n(viewings, 'total'),
      viewingsByStatus: counts(viewings['byStatus']),
      agents: [
        for (final a in (j['agents'] as List?) ?? const [])
          if (a is Map)
            (
              agentId: a['agentId'] as String,
              name: a['name'] as String? ?? a['agentId'] as String,
              leads: n(a, 'leads'),
              won: n(a, 'won'),
              viewingsDone: n(a, 'viewingsDone'),
              noShows: n(a, 'noShows'),
              replyMins: (a['replyMins'] as num?)?.toInt(),
            ),
      ],
      topListings: [
        for (final l in (j['topListings'] as List?) ?? const [])
          if (l is Map)
            (
              listingId: l['listingId'] as String,
              title: l['title'] as String? ?? '',
              agentId: l['agentId'] as String? ?? '',
              leads: n(l, 'leads'),
              calls: n(l, 'calls'),
              whatsapps: n(l, 'whatsapps'),
            ),
      ],
    );
  }

  /// Lead stages in funnel order, then any others.
  static const funnel = ['new', 'contacted', 'viewing', 'offer', 'won', 'lost'];

  /// One sheet: summary, funnel, agents, top listings, separated by blank rows.
  String toCsv() {
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = <List<Object?>>[
      ['Report', month],
      ['Leads', leads],
      ['Viewings', viewings],
      [],
      ['Lead stage', 'Leads'],
      for (final s in [...funnel, ...leadsByStage.keys.where((k) => !funnel.contains(k))]) [s, leadsByStage[s] ?? 0],
      [],
      ['Channel', 'Leads'],
      for (final e in leadsByChannel.entries) [e.key, e.value],
      [],
      ['Viewing status', 'Viewings'],
      for (final e in viewingsByStatus.entries) [e.key, e.value],
      [],
      ['Agent', 'Leads', 'Won', 'Viewings done', 'No-shows', 'Typical reply (min)'],
      for (final a in agents) [a.name, a.leads, a.won, a.viewingsDone, a.noShows, a.replyMins],
      [],
      ['Listing (all time)', 'Leads', 'Calls', 'WhatsApp'],
      for (final l in topListings) [l.title, l.leads, l.calls, l.whatsapps],
    ];
    return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }
}

/// The last [count] months, newest first, as `YYYY-MM` (Nairobi time).
List<String> reportMonths(DateTime now, {int count = 12}) {
  final n = now.toUtc().add(const Duration(hours: 3));
  return [
    for (var i = 0; i < count; i++)
      () {
        final d = DateTime.utc(n.year, n.month - i);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      }(),
  ];
}
