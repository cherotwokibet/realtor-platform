import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'providers.dart';

/// Managers read each client review before it shows on the agent's page
/// (P6-s03). Approving or hiding updates the agent's rating.
class ReviewsDialog extends ConsumerStatefulWidget {
  const ReviewsDialog({super.key});
  @override
  ConsumerState<ReviewsDialog> createState() => _ReviewsDialogState();
}

class _ReviewsDialogState extends ConsumerState<ReviewsDialog> {
  String _status = 'pending';
  List<ReviewRow>? _rows;
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _rows = null);
    final rows = await ref.read(adminRepositoryProvider).reviews(ref.read(staffProvider)!, status: _status);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _act(ReviewRow r, String action) async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(adminActionsProvider).moderateReview(ref.read(staffProvider)!, reviewId: r.id, action: action);
      _note = '${r.agentName} is now rated ${res.rating?.toStringAsFixed(1) ?? '—'} from ${res.count} '
          '${res.count == 1 ? 'review' : 'reviews'}.';
      await _load();
    } on AdminActionException catch (e) {
      _note = "Couldn't save: ${e.message}";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Reviews'),
      content: SizedBox(
        width: 600,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, children: [
            for (final s in reviewStatuses)
              ChoiceChip(
                label: Text(label(s)),
                selected: _status == s,
                onSelected: (_) {
                  setState(() => _status = s);
                  _load();
                },
              ),
          ]),
          if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: t.bodySmall)),
          const SizedBox(height: 8),
          Flexible(
            child: rows == null
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : rows.isEmpty
                    ? Text(_status == 'pending' ? 'No reviews waiting.' : 'None.', style: t.bodyMedium)
                    : ListView(shrinkWrap: true, children: [
                        for (final r in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${'★' * r.rating}${'☆' * (5 - r.rating)}  ${r.agentName}'),
                            subtitle: Text([
                              if (r.comment != null) '"${r.comment}"',
                              [r.name ?? 'No name', shortDateTime(r.createdAt)].join(' · '),
                            ].join('\n')),
                            isThreeLine: r.comment != null,
                            trailing: Wrap(spacing: 4, children: [
                              if (r.status != 'approved')
                                TextButton(onPressed: _busy ? null : () => _act(r, 'approve'), child: const Text('Approve')),
                              if (r.status != 'hidden')
                                TextButton(onPressed: _busy ? null : () => _act(r, 'hide'), child: const Text('Hide')),
                            ]),
                          ),
                      ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
