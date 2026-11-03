import 'package:flutter/material.dart';
import 'package:realtor_core/realtor_core.dart';

import 'results_map.dart' deferred as map_lib;

/// Loads the map code (flutter_map and its tile layer) the first time the
/// map is opened, so it is not part of the start-up download on the web.
/// On Android and iOS a deferred library is simply loaded at once.
class DeferredResultsMap extends StatefulWidget {
  const DeferredResultsMap({super.key, required this.hits, required this.filters, required this.onChange});
  final List<ListingSummary> hits;
  final ListingFilters filters;
  final ValueChanged<ListingFilters> onChange;

  @override
  State<DeferredResultsMap> createState() => _DeferredResultsMapState();
}

class _DeferredResultsMapState extends State<DeferredResultsMap> {
  // One load per screen; calling loadLibrary again is cheap but the Future
  // must not be recreated on every rebuild.
  late Future<void> _loaded = map_lib.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loaded,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('The map could not load.'),
              TextButton(
                onPressed: () => setState(() => _loaded = map_lib.loadLibrary()),
                child: const Text('Try again'),
              ),
            ]),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return map_lib.ResultsMap(hits: widget.hits, filters: widget.filters, onChange: widget.onChange);
      },
    );
  }
}
