import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved homes (D18): kept on this device only, no account, nothing sent.
/// A copy of each row is kept so the Saved list opens offline; the listing
/// page shows what is current.
abstract interface class FavouritesStore {
  Future<List<String>> load();
  Future<void> save(List<String> rows);
}

class PrefsFavouritesStore implements FavouritesStore {
  static const key = 'saved_homes_v1';
  @override
  Future<List<String>> load() async => (await SharedPreferences.getInstance()).getStringList(key) ?? const [];
  @override
  Future<void> save(List<String> rows) async => (await SharedPreferences.getInstance()).setStringList(key, rows);
}

final favouritesStoreProvider = Provider<FavouritesStore>((ref) => PrefsFavouritesStore());

/// Newest first; at most [maxSaved].
class FavouritesNotifier extends AsyncNotifier<List<ListingSummary>> {
  static const maxSaved = 100;

  @override
  Future<List<ListingSummary>> build() async => [
        for (final row in await ref.read(favouritesStoreProvider).load())
          if (ListingSummary.fromJson(_decode(row)) case final ListingSummary l) l,
      ];

  static Object? _decode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  bool isSaved(String id) => (state.value ?? const []).any((l) => l.id == id);

  Future<void> toggle(ListingSummary listing) async {
    final current = await future;
    final next = current.any((l) => l.id == listing.id)
        ? [for (final l in current) if (l.id != listing.id) l]
        : [listing, ...current].take(maxSaved).toList();
    state = AsyncData(next);
    await ref.read(favouritesStoreProvider).save([for (final l in next) jsonEncode(l.toJson())]);
  }
}

final favouritesProvider = AsyncNotifierProvider<FavouritesNotifier, List<ListingSummary>>(FavouritesNotifier.new);

/// The heart on a listing: saves or removes it on this device.
class FavouriteButton extends ConsumerWidget {
  const FavouriteButton({super.key, required this.listing});
  final ListingSummary listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = (ref.watch(favouritesProvider).value ?? const []).any((l) => l.id == listing.id);
    return IconButton(
      tooltip: saved ? 'Remove from saved' : 'Save this home',
      icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
      color: saved ? Theme.of(context).colorScheme.primary : null,
      onPressed: () => ref.read(favouritesProvider.notifier).toggle(listing),
    );
  }
}
