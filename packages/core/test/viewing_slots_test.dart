import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('half-hour times from 08:00 to 17:30', () {
    expect(viewingTimes.first, '08:00');
    expect(viewingTimes.last, '17:30');
    expect(viewingTimes, hasLength(20));
  });

  test('days start today in Nairobi and skip Sundays', () {
    // 22:30 UTC on Saturday 31 Oct is already Sunday 1 Nov in Nairobi.
    final days = viewingDays(DateTime.utc(2026, 10, 31, 22, 30), count: 3);
    expect(days.map((d) => d.value), ['2026-11-02', '2026-11-03', '2026-11-04']);
    expect(days.first.label, 'Mon 2 Nov');
  });

  test('slots carry the Nairobi offset', () {
    expect(viewingSlot('2026-10-27', '10:30'), '2026-10-27T10:30:00+03:00');
  });
}
