import 'admin_repository.dart';

/// The admin's week calendar (P5-s05): each day in Nairobi time (UTC+3 all
/// year, as viewing slots are) with its viewings and the agents' time off.

const _nairobi = Duration(hours: 3);
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Viewings the calendar shows: every one still happening or that happened.
const calendarViewingStatuses = ['requested', 'confirmed', 'done', 'no-show'];

/// Monday 00:00 in Nairobi of the week holding [t], as a UTC instant.
DateTime weekStart(DateTime t) {
  final n = t.toUtc().add(_nairobi);
  final day = DateTime.utc(n.year, n.month, n.day);
  return day.subtract(Duration(days: day.weekday - 1)).subtract(_nairobi);
}

/// `HH:mm` in Nairobi.
String nairobiTime(DateTime t) {
  final n = t.toUtc().add(_nairobi);
  return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

/// `Mon 2 Nov`, for the Nairobi day starting at [dayStart].
String nairobiDayLabel(DateTime dayStart) {
  final n = dayStart.toUtc().add(_nairobi);
  return '${_days[n.weekday - 1]} ${n.day} ${_months[n.month - 1]}';
}

/// One line in a day: a viewing, or an agent's time off that day.
class CalendarEntry {
  const CalendarEntry._(this.at, this.time, {this.viewing, this.block});
  final DateTime at;

  /// `10:30` for a viewing; for time off `All day`, `10:00–14:00`,
  /// `from 10:00` or `until 14:00`, cut to the day.
  final String time;
  final ViewingRow? viewing;
  final AgentBlock? block;
}

class CalendarDay {
  const CalendarDay(this.start, this.label, this.entries);
  final DateTime start;
  final String label;
  final List<CalendarEntry> entries;
}

/// The seven days from [start] (a [weekStart]), each with the viewings in
/// [calendarViewingStatuses] and the time off that touches it, by time.
List<CalendarDay> calendarWeek(DateTime start, Iterable<ViewingRow> viewings, Iterable<AgentBlock> blocks) {
  return [
    for (var i = 0; i < 7; i++) _day(start.add(Duration(days: i)), viewings, blocks),
  ];
}

CalendarDay _day(DateTime from, Iterable<ViewingRow> viewings, Iterable<AgentBlock> blocks) {
  final to = from.add(const Duration(days: 1));
  bool inDay(DateTime t) => !t.isBefore(from) && t.isBefore(to);
  final entries = [
    for (final v in viewings)
      if (calendarViewingStatuses.contains(v.status) && inDay(v.slot)) CalendarEntry._(v.slot, nairobiTime(v.slot), viewing: v),
    for (final b in blocks)
      if (b.start.isBefore(to) && b.end.isAfter(from)) _blockEntry(b, from, to),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return CalendarDay(from, nairobiDayLabel(from), entries);
}

CalendarEntry _blockEntry(AgentBlock b, DateTime from, DateTime to) {
  final startsToday = b.start.isAfter(from), endsToday = b.end.isBefore(to);
  final time = switch ((startsToday, endsToday)) {
    (true, true) => '${nairobiTime(b.start)}–${nairobiTime(b.end)}',
    (true, false) => 'from ${nairobiTime(b.start)}',
    (false, true) => 'until ${nairobiTime(b.end)}',
    (false, false) => 'All day',
  };
  return CalendarEntry._(startsToday ? b.start : from, time, block: b);
}
