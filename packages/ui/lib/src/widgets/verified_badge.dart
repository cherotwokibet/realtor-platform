import 'package:flutter/material.dart';

import '../brand_theme.dart';

/// "Verified" chip shown on listings an agent re-confirmed in the last 30 days.
/// Whether a listing is verified is decided server-side (verifiedAt/expiresAt);
/// this widget only displays it.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verifiedAt, this.label = 'Verified'});

  final DateTime verifiedAt;
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Semantics(
      label: '$label on ${MaterialLocalizations.of(context).formatShortDate(verifiedAt)}',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: b.spacing.xs / 2),
        decoration: BoxDecoration(
          color: b.accent,
          borderRadius: BorderRadius.circular(b.radiusSm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified, size: 14, color: b.onAccent),
          SizedBox(width: b.spacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: b.onAccent)),
        ]),
      ),
    );
  }
}
