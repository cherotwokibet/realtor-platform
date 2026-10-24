import 'package:flutter/material.dart';
import 'package:realtor_core/realtor_core.dart';

/// "KES 45,000 /month" with the period muted.
class PriceText extends StatelessWidget {
  const PriceText(this.amountKes, {super.key, this.period, this.compact = false, this.style});

  final int amountKes;

  /// e.g. 'month' for rent; null for sale prices.
  final String? period;
  final bool compact;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.titleMedium!.copyWith(color: theme.colorScheme.primary);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: formatKes(amountKes, compact: compact), style: base),
        if (period != null)
          TextSpan(text: ' /$period', style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
