const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "27 Oct 2026, 09:05" in the viewer's local time (Nairobi for the realtor's staff).
String shortDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day} ${_months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

/// Stored values whose label isn't plain sentence case.
const _labels = {'whatsapp': 'WhatsApp'};

/// "lead.stage" → "Lead stage", "south-b" → "South b": labels from stored values.
String label(String value) {
  final known = _labels[value];
  if (known != null) return known;
  final s = value.replaceAll(RegExp('[._-]'), ' ');
  return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// "25 min", "2 h", "3 days": a reply time or a wait, rounded to what a person reads.
String minutesLabel(int mins) => switch (mins) {
      < 60 => '$mins min',
      < 1440 => '${(mins / 60).round()} h',
      _ => '${(mins / 1440).round()} ${(mins / 1440).round() == 1 ? 'day' : 'days'}',
    };

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "Friday, 20 November".
String longDate(DateTime t) {
  final l = t.toLocal();
  return '${_weekdays[l.weekday - 1]}, ${l.day} ${_monthNames[l.month - 1]}';
}

/// "20 Nov".
String shortDate(DateTime t) {
  final l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}

/// "09:30".
String timeOfDay(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// "just now", "25 min ago", "3 h ago", "2 days ago", or the date past a week.
String ago(DateTime t, DateTime now) {
  final m = now.difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  if (m < 1440) return '${m ~/ 60} h ago';
  final d = m ~/ 1440;
  return d < 7 ? '$d ${d == 1 ? 'day' : 'days'} ago' : shortDate(t);
}
