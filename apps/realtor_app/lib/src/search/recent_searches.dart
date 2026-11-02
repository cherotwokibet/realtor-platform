import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_screen.dart';

/// Recent searches (P4-s02): the last few filter URLs, kept on this device
/// only (like saved homes, D18), offered again on the home screen.
abstract interface class RecentSearchesStore {
  Future<List<String>> load();
  Future<void> save(List<String> uris);
}

class PrefsRecentSearchesStore implements RecentSearchesStore {
  static const key = 'recent_searches_v1';
  @override
  Future<List<String>> load() async => (await SharedPreferences.getInstance()).getStringList(key) ?? const [];
  @override
  Future<void> save(List<String> uris) async => (await SharedPreferences.getInstance()).setStringList(key, uris);
}

final recentSearchesStoreProvider = Provider<RecentSearchesStore>((ref) => PrefsRecentSearchesStore());

/// Newest first, at most [maxKept], each search once (whatever page or sort).
class RecentSearchesNotifier extends AsyncNotifier<List<ListingFilters>> {
  static const maxKept = 5;

  @override
  Future<List<ListingFilters>> build() async => [
        for (final s in await ref.read(recentSearchesStoreProvider).load())
          if (Uri.tryParse(s) case final Uri u)
            if (ListingFilters.fromUri(u) case final ListingFilters f) f,
      ];

  /// Remembers [f] unless it narrows nothing (a bare "Rent" is the home screen's job).
  Future<void> record(ListingFilters f) async {
    final narrows = f.q != null || f.types.isNotEmpty || f.areas.isNotEmpty || f.minBeds != null || f.maxPriceKES != null || f.near != null;
    if (!narrows) return;
    final key = _key(f);
    final current = await future;
    final next = [f.copyWith(sort: ListingSort.newest), ...current.where((c) => _key(c) != key)].take(maxKept).toList();
    state = AsyncData(next);
    await ref.read(recentSearchesStoreProvider).save([for (final s in next) s.toUri().toString()]);
  }

  Future<void> clear() async {
    state = const AsyncData([]);
    await ref.read(recentSearchesStoreProvider).save(const []);
  }

  static String _key(ListingFilters f) => f.copyWith(sort: ListingSort.newest).toUri().toString();
}

final recentSearchesProvider = AsyncNotifierProvider<RecentSearchesNotifier, List<ListingFilters>>(RecentSearchesNotifier.new);

/// What a recent search is called on its chip.
String recentLabel(ListingFilters f) => [describeSearch(f), if (f.q != null) '"${f.q}"', if (f.near != null) 'near a place'].join(' · ');

/// Records [filters] as a recent search when shown, and again whenever they change.
class RecordSearch extends ConsumerStatefulWidget {
  const RecordSearch({super.key, required this.filters, required this.child});
  final ListingFilters filters;
  final Widget child;

  @override
  ConsumerState<RecordSearch> createState() => _RecordSearchState();
}

class _RecordSearchState extends ConsumerState<RecordSearch> {
  @override
  void initState() {
    super.initState();
    _record();
  }

  @override
  void didUpdateWidget(RecordSearch old) {
    super.didUpdateWidget(old);
    if (old.filters.toUri() != widget.filters.toUri()) _record();
  }

  // After the frame: providers may not change while the tree is building.
  void _record() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(recentSearchesProvider.notifier).record(widget.filters);
      });

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The home screen's "Recent searches" chips; nothing until there is one.
class RecentSearches extends ConsumerWidget {
  const RecentSearches({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider).value ?? const [];
    if (recent.isEmpty) return const SizedBox.shrink();
    final b = context.brand;
    return Padding(
      padding: EdgeInsets.only(top: b.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('Recent searches', style: Theme.of(context).textTheme.titleSmall)),
            TextButton(onPressed: () => ref.read(recentSearchesProvider.notifier).clear(), child: const Text('Clear')),
          ]),
          Wrap(
            spacing: b.spacing.sm,
            runSpacing: b.spacing.sm,
            children: [
              for (final f in recent)
                ActionChip(
                  avatar: const Icon(Icons.history, size: 18),
                  label: Text(recentLabel(f)),
                  onPressed: () => context.go(f.toUri().toString()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
