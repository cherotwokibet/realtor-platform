import 'dart:convert';
import 'dart:io';

import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_tokens/realtor_tokens.dart';
import 'package:test/test.dart';

void main() {
  final tenant = TenantConfig.fromJson(
    jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>,
  );
  final tokens = Tokens(tenant);

  test('hex round-trips', () {
    expect(hex(0xFF5E0202), '#5E0202');
    expect(hex(parseHexColor('#0055FF')), '#0055FF');
  });

  test('spacing follows the 4 px grid', () {
    expect(tokens.spacing.lg, 16);
    expect(tokens.spacing.gutter, 16);
  });

  test('css carries brand values', () {
    final css = tokens.toCss();
    expect(css, contains('--color-primary: #5E0202;'));
    expect(css, contains('--color-on-primary: #FFFFFF;'));
    expect(css, contains('--text-body: 0.875rem;'));
    expect(css, contains('--radius-md: 12px;'));
    expect(css, contains('--font-display: "Poppins"'));
  });
}
