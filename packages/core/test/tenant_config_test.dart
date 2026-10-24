import 'dart:convert';
import 'dart:io';

import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

Map<String, Object?> load(String id) =>
    jsonDecode(File('../../tenants/$id.json').readAsStringSync()) as Map<String, Object?>;

void main() {
  group('TenantConfig', () {
    test('parses every tenant file in the repo', () {
      final files = Directory('../../tenants')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'));
      expect(files.length, greaterThanOrEqualTo(2));
      for (final f in files) {
        final t = TenantConfig.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, Object?>);
        expect(f.path, endsWith('${t.id}.json'));
      }
    });

    test('Realtime Estates values come through', () {
      final t = TenantConfig.fromJson(load('realtime-estates'));
      expect(t.name, 'Realtime Estates Ltd');
      expect(t.brand.colors.primary, 0xFF5E0202);
      expect(t.brand.displayFont, 'Poppins');
      expect(t.firebaseProjects[FirebaseEnv.prod], 'rte-realtor-prod');
      expect(t.features.mpesa, isFalse);
      expect(t.currency, 'KES');
      expect(t.hasContactNumbers, isFalse);
      expect(t.whatsappLink('hi'), isNull);
    });

    test('two tenants differ only by data', () {
      final a = TenantConfig.fromJson(load('realtime-estates'));
      final b = TenantConfig.fromJson(load('demo-homes'));
      expect(a.brand.colors.primary, isNot(b.brand.colors.primary));
      expect(a.androidId, isNot(b.androidId));
    });

    test('rejects a bad colour', () {
      final j = load('realtime-estates');
      ((j['brand']! as Map<String, Object?>)['colors']! as Map<String, Object?>)['primary'] = 'maroon';
      expect(() => TenantConfig.fromJson(j), throwsA(isA<TenantConfigException>()));
    });

    test('rejects an unknown schema version', () {
      final j = load('realtime-estates')..['schemaVersion'] = 2;
      expect(() => TenantConfig.fromJson(j), throwsA(isA<TenantConfigException>()));
    });
  });

  group('formatKes', () {
    test('groups thousands', () {
      expect(formatKes(45000), 'KES 45,000');
      expect(formatKes(1250000), 'KES 1,250,000');
      expect(formatKes(800), 'KES 800');
    });
    test('compact', () {
      expect(formatKes(4500000, compact: true), 'KES 4.5M');
      expect(formatKes(12000000, compact: true), 'KES 12M');
      expect(formatKes(150000, compact: true), 'KES 150K');
      expect(formatKes(45000, compact: true), 'KES 45,000');
    });
  });
}
