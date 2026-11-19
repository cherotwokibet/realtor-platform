import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// My Activity, as on Bayut: the homes viewed and the ones whose agent was
/// called, sent a WhatsApp or emailed, kept on this device only (like recent
/// searches and saved homes before sign-in), newest first.
typedef ActivityEntry = ({ListingSummary home, DateTime at, String? channel});

enum ActivityKind { viewed, contacted }

abstract interface class ActivityStore {
  Future<List<ActivityEntry>> load(ActivityKind kind);
  Future<void> save(ActivityKind kind, List<ActivityEntry> entries);
}

class PrefsActivityStore implements ActivityStore {
  static String key(ActivityKind k) => 'activity_${k.name}_v1';

  @override
  Future<List<ActivityEntry>> load(ActivityKind kind) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key(kind));
      if (raw == null) return const [];
      return [
        for (final e in (jsonDecode(raw) as List).whereType<Map<String, Object?>>())
          if (ListingSummary.fromJson(e['home']) case final ListingSummary h)
            (home: h, at: DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt()), channel: e['channel'] as String?),
      ];
    } on Object {
      return const []; // a damaged copy is ignored
    }
  }

  @override
  Future<void> save(ActivityKind kind, List<ActivityEntry> entries) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        key(kind),
        jsonEncode([
          for (final e in entries) {'home': e.home.toJson(), 'at': e.at.millisecondsSinceEpoch, if (e.channel != null) 'channel': e.channel},
        ]),
      );
    } on Object {
      // Storage full or blocked: the activity is simply not kept.
    }
  }
}

final activityStoreProvider = Provider<ActivityStore>((ref) => PrefsActivityStore());

class ActivityNotifier extends AsyncNotifier<List<ActivityEntry>> {
  ActivityNotifier(this.kind);
  final ActivityKind kind;

  /// How many homes each list keeps.
  static const maxKept = 50;

  @override
  Future<List<ActivityEntry>> build() => ref.read(activityStoreProvider).load(kind);

  /// Puts [home] first (each home once), with the time and how they got in touch.
  Future<void> record(ListingSummary home, {String? channel, DateTime? at}) async {
    final current = await future;
    final next = [(home: home, at: at ?? DateTime.now(), channel: channel), ...current.where((e) => e.home.id != home.id)].take(maxKept).toList();
    state = AsyncData(next);
    await ref.read(activityStoreProvider).save(kind, next);
  }

  Future<void> clear() async {
    state = const AsyncData([]);
    await ref.read(activityStoreProvider).save(kind, const []);
  }
}

final activityProvider = AsyncNotifierProvider.family<ActivityNotifier, List<ActivityEntry>, ActivityKind>(ActivityNotifier.new);

/// Records a view of [home] once, when the listing page first shows.
class RecordView extends ConsumerStatefulWidget {
  const RecordView({super.key, required this.home, required this.child});
  final ListingSummary home;
  final Widget child;

  @override
  ConsumerState<RecordView> createState() => _RecordViewState();
}

class _RecordViewState extends ConsumerState<RecordView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(activityProvider(ActivityKind.viewed).notifier).record(widget.home).ignore();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Today", "Yesterday", or "15th November, 2026", as Bayut heads the days.
String activityDay(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day), today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final d = at.day;
  final suffix = (d % 100 >= 11 && d % 100 <= 13) ? 'th' : switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$d$suffix ${months[at.month - 1]}, ${at.year}';
}
