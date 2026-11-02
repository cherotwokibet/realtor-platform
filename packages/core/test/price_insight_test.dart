import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('only a rent clearly below the median counts', () {
    expect(percentBelowTypical(65000, 75000), 13);
    expect(percentBelowTypical(72000, 75000), isNull, reason: '4%: noise');
    expect(percentBelowTypical(71250, 75000), 5);
    expect(percentBelowTypical(80000, 75000), isNull);
    expect(percentBelowTypical(65000, null), isNull);
  });
}
