import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

ViewingRow viewing(String id, DateTime slot, {String status = 'confirmed'}) => ViewingRow(
      id: id,
      listingId: 'l1',
      listingTitle: 'Two bed in Kilimani',
      agentId: 'a1',
      agentName: 'Agent One',
      slot: slot,
      status: status,
    );

AgentBlock block(String id, DateTime start, DateTime end) =>
    AgentBlock(id: id, agentId: 'a1', agentName: 'Agent One', start: start, end: end);

/// Nairobi wall-clock time as a UTC instant.
DateTime eat(int y, int m, int d, [int h = 0, int min = 0]) => DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 3));

void main() {
  test('the week starts on Monday at midnight in Nairobi', () {
    // Wed 4 Nov 2026, 10:00 Nairobi.
    expect(weekStart(eat(2026, 11, 4, 10)), eat(2026, 11, 2));
    // Sunday late evening still belongs to the week that began on Monday.
    expect(weekStart(eat(2026, 11, 8, 23, 30)), eat(2026, 11, 2));
    // Monday 01:00 Nairobi is still Sunday 22:00 UTC: Nairobi decides.
    expect(weekStart(eat(2026, 11, 9, 1)), eat(2026, 11, 9));
    expect(nairobiDayLabel(eat(2026, 11, 2)), 'Mon 2 Nov');
    expect(nairobiTime(eat(2026, 11, 2, 9, 30)), '09:30');
  });

  test('each day lists its viewings by time; cancelled ones are left out', () {
    final days = calendarWeek(eat(2026, 11, 2), [
      viewing('late', eat(2026, 11, 3, 15)),
      viewing('early', eat(2026, 11, 3, 9, 30), status: 'requested'),
      viewing('gone', eat(2026, 11, 3, 11), status: 'cancelled'),
      viewing('sat', eat(2026, 11, 7, 17, 30), status: 'done'),
      viewing('next-week', eat(2026, 11, 9, 9)),
    ], []);
    expect(days.map((d) => d.label), ['Mon 2 Nov', 'Tue 3 Nov', 'Wed 4 Nov', 'Thu 5 Nov', 'Fri 6 Nov', 'Sat 7 Nov', 'Sun 8 Nov']);
    expect(days[0].entries, isEmpty);
    expect(days[1].entries.map((e) => (e.time, e.viewing!.id)), [('09:30', 'early'), ('15:00', 'late')]);
    expect(days[5].entries.single.viewing!.id, 'sat');
    expect(days.expand((d) => d.entries).any((e) => e.viewing?.id == 'next-week'), isFalse);
  });

  test('time off shows on every day it touches, cut to the day', () {
    final days = calendarWeek(eat(2026, 11, 2), [viewing('v', eat(2026, 11, 2, 9))], [
      block('short', eat(2026, 11, 2, 10), eat(2026, 11, 2, 14)),
      block('long', eat(2026, 11, 4, 13), eat(2026, 11, 6, 12)),
    ]);
    expect(days[0].entries.map((e) => e.time), ['09:00', '10:00–14:00']);
    expect(days[0].entries.last.block!.id, 'short');
    expect(days[2].entries.single.time, 'from 13:00');
    expect(days[3].entries.single.time, 'All day');
    expect(days[4].entries.single.time, 'until 12:00');
    expect(days[5].entries, isEmpty);
  });
}
