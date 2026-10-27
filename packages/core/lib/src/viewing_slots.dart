/// Viewing slots offered by the app and the share pages. They mirror
/// `VIEWING_RULES` in functions/src/api/viewings.ts, which has the final
/// say: half-hour starts 08:00-17:30 Nairobi time (UTC+3 all year),
/// Monday to Saturday.
final viewingTimes = [
  for (var m = 8 * 60; m <= 17 * 60 + 30; m += 30)
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
];

/// The next [count] viewing days (no Sundays), from today in Nairobi:
/// value `2026-10-27`, label `Tue 27 Oct`.
List<({String value, String label})> viewingDays(DateTime now, {int count = 12}) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final nairobi = now.toUtc().add(const Duration(hours: 3));
  var d = DateTime.utc(nairobi.year, nairobi.month, nairobi.day);
  final out = <({String value, String label})>[];
  while (out.length < count) {
    if (d.weekday != DateTime.sunday) {
      final value = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      out.add((value: value, label: '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}'));
    }
    d = d.add(const Duration(days: 1));
  }
  return out;
}

/// A day value and a time from the lists above, as the ISO slot the
/// `bookViewing` Function takes: `2026-10-27T10:30:00+03:00`.
String viewingSlot(String day, String time) => '${day}T$time:00+03:00';
