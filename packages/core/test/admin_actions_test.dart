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
}
