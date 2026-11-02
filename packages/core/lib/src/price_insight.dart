/// Price insights (P7-s03): how a rental compares with its area's typical
/// rent (`areas.stats.medianRentKES`, refreshed nightly from live rentals).
library;

/// Below this many percent, the difference is noise and nothing is shown.
const insightThresholdPercent = 5;

/// Whole percent below [median], or null when the rent is not clearly
/// below it (or there is no median).
int? percentBelowTypical(int rentKES, int? median) {
  if (median == null || median <= 0 || rentKES <= 0) return null;
  final pct = ((median - rentKES) * 100 / median).floor();
  return pct >= insightThresholdPercent ? pct : null;
}
