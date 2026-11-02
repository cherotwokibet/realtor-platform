import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  final r = MonthlyReport.fromJson({
    'month': '2026-10',
    'leads': {'total': 3, 'byChannel': {'form': 2, 'viewing': 1}, 'byStage': {'won': 1, 'new': 2}},
    'viewings': {'total': 1, 'byStatus': {'done': 1}},
    'agents': [
      {'agentId': 'a1', 'name': 'Achieng, O.', 'leads': 3, 'won': 1, 'viewingsDone': 1, 'noShows': 0, 'replyMins': 25},
    ],
    'topListings': [
      {'listingId': 'l1', 'title': '2 bedroom "garden" flat', 'agentId': 'a1', 'leads': 7, 'calls': 3, 'whatsapps': 4},
    ],
  });

  test('reads the Function answer', () {
    expect((r.month, r.leads, r.viewings, r.leadsByChannel['form'], r.agents.single.replyMins, r.topListings.single.leads),
        ('2026-10', 3, 1, 2, 25, 7));
  });

  test('CSV: funnel in order, quoted where needed, CRLF', () {
    final csv = r.toCsv();
    expect(csv, startsWith('Report,2026-10\r\nLeads,3\r\nViewings,1\r\n\r\nLead stage,Leads\r\nnew,2\r\ncontacted,0\r\n'));
    expect(csv, contains('"Achieng, O.",3,1,1,0,25\r\n'));
    expect(csv, contains('"2 bedroom ""garden"" flat",7,3,4\r\n'));
  });

  test('report months: the last twelve, newest first, in Nairobi time', () {
    final m = reportMonths(DateTime.utc(2026, 10, 31, 22)); // 1 Nov 01:00 in Nairobi
    expect(m.take(3), ['2026-11', '2026-10', '2026-09']);
    expect(m.last, '2025-12');
  });
}
