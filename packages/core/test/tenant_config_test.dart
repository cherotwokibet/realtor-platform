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
      expect(t.hasContactNumbers, isTrue);
      expect(t.whatsappLink('hi').toString(), 'https://wa.me/254722311918?text=hi');
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

  group('Features', () {
    test('every enum value maps to its JSON key', () {
      final json = {for (final f in Feature.values) f.name: f == Feature.ads};
      final features = Features.fromJson(json);
      for (final f in Feature.values) {
        expect(features.isOn(f), f == Feature.ads, reason: f.name);
      }
    });

    test('copyWith flips only what it is given', () {
      final t = TenantConfig.fromJson(load('demo-homes'));
      final off = t.features.copyWith({Feature.chat: false});
      expect(off.chat, isFalse);
      for (final f in Feature.values.where((f) => f != Feature.chat)) {
        expect(off.isOn(f), t.features.isOn(f), reason: f.name);
      }
      expect(t.withFeatures(off).features.chat, isFalse);
      expect(t.withFeatures(off).name, t.name);
    });
  });

  group('home content', () {
    test('the realtor\'s words, and whether each band names a photo', () {
      final json = load('demo-homes');
      final t = TenantConfig.fromJson(json);
      expect(t.home.hero!.title, isNotEmpty);
      expect(t.home.hero!.hasImage, isFalse);
      (json['home'] as Map<String, Object?>)['hero'] = {'title': 'Welcome', 'image': 'brand/demo-homes/home/hero.jpg'};
      final withPhoto = TenantConfig.fromJson(json);
      expect(withPhoto.home.hero!.hasImage, isTrue);
      expect(withPhoto.home.hero!.text, isNull);
      expect(withPhoto.home.hero!.imageCount, 1);
      expect(withPhoto.withFeatures(withPhoto.features).home.hero!.title, 'Welcome');
      (json['home'] as Map<String, Object?>)['hero'] = {'title': 'Welcome', 'images': ['brand/x/home/1.jpg', 'brand/x/home/2.jpg', 'brand/x/home/3.jpg']};
      expect(TenantConfig.fromJson(json).home.hero!.imageCount, 3);
    });

    test('a tenant file without `home` has no bands', () {
      final json = load('demo-homes')..remove('home');
      final t = TenantConfig.fromJson(json);
      expect(t.home.hero, isNull);
      expect(t.home.banner, isNull);
    });
  });
}
