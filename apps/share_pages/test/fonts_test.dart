import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

TenantConfig tenant(String id) => TenantConfig.fromJson(
  jsonDecode(File('../../tenants/$id.json').readAsStringSync())
      as Map<String, Object?>,
);

Future<shelf.Response> get(
  TenantConfig t,
  String path, {
  String? fontsDir = '../../fonts',
}) => Future.value(
  shareHandler(t, InMemoryListingSource(const []), fontsDir: fontsDir)(
    shelf.Request('GET', Uri.parse('https://x$path')),
  ),
);

void main() {
  setUpAll(Jaspr.initializeApp);
  final tenants = [
    for (final f in Directory(
      '../../tenants',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
      tenant(f.uri.pathSegments.last.replaceAll('.json', '')),
  ];

  test(
    'every tenant gets @font-face for exactly its own families, four weights each',
    () {
      expect(tenants.length, greaterThanOrEqualTo(2));
      for (final t in tenants) {
        final css = fontFaceCss(t);
        final families = {t.brand.displayFont, t.brand.bodyFont};
        expect(
          RegExp('@font-face').allMatches(css).length,
          families.length * 4,
        );
        for (final family in families) {
          expect(css, contains('font-family:"$family";font-weight:600'));
        }
        expect(css, contains('font-display:swap'));
      }
    },
  );

  test('a re-brand changes the fonts on the page with no code change', () {
    final fonts = {for (final t in tenants) t.id: tenantFamilies(t).join('+')};
    expect(
      fonts.values.toSet().length,
      greaterThan(1),
      reason: 'tenants should differ: $fonts',
    );
  });

  test('pages carry the font-face rules', () async {
    final t = tenants.first;
    final r = await get(t, '/');
    expect(
      await r.readAsString(),
      contains('@font-face{font-family:"${t.brand.bodyFont}"'),
    );
  });

  test('every @font-face file is served as TTF with a long cache', () async {
    for (final t in tenants) {
      for (final m in RegExp(
        r'url\((/fonts/[^)]+)\)',
      ).allMatches(fontFaceCss(t))) {
        final r = await get(t, m[1]!);
        expect(r.statusCode, 200, reason: m[1]);
        expect(r.headers['content-type'], 'font/ttf');
        expect(r.headers['cache-control'], contains('max-age=2592000'));
        expect((await r.read().expand((c) => c).length), greaterThan(10000));
      }
    }
  });

  test(
    'only the tenant\'s own fonts are served; nothing else in the folder',
    () async {
      final t = tenants.first;
      final other = [
        'Poppins',
        'Inter',
        'Manrope',
      ].firstWhere((f) => !tenantFamilies(t).contains(f));
      expect((await get(t, '/fonts/$other-Regular.ttf')).statusCode, 404);
      expect((await get(t, '/fonts/OFL.txt')).statusCode, 404);
      expect(
        (await get(
          t,
          '/fonts/..%2F..%2Ftenants%2Frealtime-estates.json',
        )).statusCode,
        404,
      );
      expect(
        (await get(
          t,
          '/fonts/${tenantFamilies(t).first}-Regular.ttf',
          fontsDir: null,
        )).statusCode,
        404,
      );
    },
  );

  test('the CSP lets the page load its own fonts and nothing else', () {
    final csp = securityHeaders['content-security-policy']!;
    expect(csp, contains("font-src 'self'"));
    expect(csp, contains("default-src 'none'"));
  });

  test('every tenant\'s header logo is served from its brand folder, and the pages load it from there', () async {
    for (final t in tenants) {
      final h = shareHandler(t, InMemoryListingSource(const []), brandDir: '../../brand/${t.id}');
      final r = await h(shelf.Request('GET', Uri.parse('https://x$logoPath')));
      expect(r.statusCode, 200, reason: t.id);
      expect(r.headers['content-type'], 'image/svg+xml');
      expect(await r.readAsString(), startsWith('<svg'), reason: t.id);
      final home = await (await h(shelf.Request('GET', Uri.parse('https://x/')))).readAsString();
      expect(home, contains('src="$logoPath"'), reason: t.id);
    }
    final none = await get(tenants.first, logoPath);
    expect(none.statusCode, 404, reason: 'no brandDir, no logo route');
  });
}
