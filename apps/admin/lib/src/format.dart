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
