import 'package:flutter/widgets.dart';
import 'package:realtor_core/realtor_core.dart';

import 'tenant_scope.dart';

extension FeatureContext on BuildContext {
  /// The tenant's feature switches.
  Features get features => TenantScope.of(this).features;
}

/// Shows [child] only when the tenant has [feature] on; otherwise [orElse]
/// (nothing by default). Every feature-specific widget goes through this, so
/// switching a feature off in the tenant file removes it everywhere.
class FeatureGate extends StatelessWidget {
  const FeatureGate({super.key, required this.feature, required this.child, this.orElse});

  final Feature feature;
  final Widget child;
  final Widget? orElse;

  /// Key on the gated subtree, so tests can find every place a feature shows.
  static Key keyFor(Feature f) => ValueKey('feature:${f.name}');

  @override
  Widget build(BuildContext context) => context.features.isOn(feature)
      ? KeyedSubtree(key: keyFor(feature), child: child)
      : orElse ?? const SizedBox.shrink();
}
