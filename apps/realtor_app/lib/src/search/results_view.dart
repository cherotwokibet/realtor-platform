import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Results as a list or on the map (P3-s04, P4-s02). Kept while filters
/// change, so drawing an area or removing a chip stays on the map.
class ResultsViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool map) => state = map;
}

final resultsOnMapProvider = NotifierProvider<ResultsViewNotifier, bool>(ResultsViewNotifier.new);
