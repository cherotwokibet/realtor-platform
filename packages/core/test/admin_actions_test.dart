import 'dart:convert';
import 'dart:io';

import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('the move tables match the ones the Functions enforce', () {
    final json =
        jsonDecode(File('../../functions/src/model/transitions.json').readAsStringSync()) as Map<String, Object?>;
    expect(json['leadStage'], leadStageMoves);
    expect(json['listingStatus'], listingStatusMoves);
    expect(json['moderation'], moderationTargets);
    expect(json['viewingStatus'], viewingStatusMoves);
    expect(viewingStatusMoves.keys, unorderedEquals(viewingStatuses));
    expect(leadStageMoves.keys, unorderedEquals(leadStages));
    expect(listingStatusMoves.keys, unorderedEquals(listingStatuses));
  });

  test('next lead stages', () {
    expect(nextLeadStages('new'), ['contacted', 'lost']);
    expect(nextLeadStages('won'), isEmpty);
    expect(nextLeadStages('unknown'), isEmpty);
  });

  test('moderation actions per status', () {
    expect(moderationsFor('pending'), ['approve', 'reject']);
    expect(moderationsFor('live'), ['reject', 'expire', 'let', 'sold']);
    expect(moderationsFor('expired'), ['approve']);
    expect(moderationsFor('let'), ['approve']);
    expect(moderationsFor('draft'), isEmpty);
    expect(moderationsFor('sold'), isEmpty);
  });

  test('viewings are marked done or no-show only after their time', () {
    final slot = DateTime.utc(2026, 10, 26, 7, 30);
    expect(nextViewingStatuses('confirmed', slot, slot.subtract(const Duration(hours: 1))), ['cancelled']);
    expect(nextViewingStatuses('confirmed', slot, slot.add(const Duration(minutes: 1))), ['done', 'no-show', 'cancelled']);
    expect(nextViewingStatuses('requested', slot, slot), ['confirmed', 'cancelled']);
    expect(nextViewingStatuses('done', slot, slot), isEmpty);
  });
}
