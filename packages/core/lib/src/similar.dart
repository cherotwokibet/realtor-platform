import 'listing_filters.dart';
import 'listing_search.dart';

/// What "similar" compares: the app and the share pages each map their own
/// listing type to this, so both rank the same way (P7-s04).
typedef SimilarKey = ({String id, Purpose purpose, String area, String type, int beds, int priceKES});

/// Up to [count] of [pool] most like [of]: same purpose always, then the same
/// area, type, bedrooms and a price within a quarter (or half) of it count
/// toward a score. A home must share the area or the type, and be within half
/// the price, to be offered at all; ties go to the closer price. [of] itself
/// and repeats are left out.
List<T> similarListings<T>(T of, Iterable<T> pool, SimilarKey Function(T) key, {int count = 3}) {
  final me = key(of);
  final seen = <String>{me.id};
  final scored = <({T item, int score, int gap})>[];
  for (final item in pool) {
    final k = key(item);
    if (k.purpose != me.purpose || !seen.add(k.id)) continue;
    final gap = (k.priceKES - me.priceKES).abs();
    final sameArea = k.area == me.area, sameType = k.type == me.type;
    if (!(sameArea || sameType) || gap * 2 > me.priceKES) continue;
    final score = (sameArea ? 3 : 0) + (sameType ? 2 : 0) + (k.beds == me.beds ? 1 : 0) + (gap * 4 <= me.priceKES ? 2 : 1);
    scored.add((item: item, score: score, gap: gap));
  }
  scored.sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : a.gap.compareTo(b.gap));
  return [for (final s in scored.take(count)) s.item];
}

/// [SimilarKey] for a search row (the app).
SimilarKey similarKey(ListingSummary l) => (id: l.id, purpose: l.purpose, area: l.area, type: l.type, beds: l.beds, priceKES: l.priceKES);
