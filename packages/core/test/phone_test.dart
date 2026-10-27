import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('accepts the ways people type Kenyan mobiles', () {
    for (final s in ['0712345678', '0712 345 678', '+254712345678', '+254 712-345-678', '254712345678', '712345678', '(0712) 345678']) {
      expect(normaliseKenyanPhone(s), '+254712345678', reason: s);
    }
    expect(normaliseKenyanPhone('0110 123 456'), '+254110123456');
  });

  test('rejects landlines, short numbers, other countries and text', () {
    for (final s in ['020 2345678', '071234567', '07123456789', '+255712345678', 'call me', '', '+254812345678']) {
      expect(normaliseKenyanPhone(s), isNull, reason: s);
    }
  });
}
