import 'dart:convert';
import 'dart:io';

import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

Map<String, Object?> tenantJson() =>
    jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>;

const fingerprint = '14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5';

TenantConfig withStoreIds() {
  final j = tenantJson();
  (j['apps']! as Map)
    ..['androidCertSha256'] = [fingerprint]
    ..['appleTeamId'] = 'ABCDE12345';
  return TenantConfig.fromJson(j);
}

Future<shelf.Response> get(TenantConfig t, String path) =>
    Future.value(shareHandler(t, InMemoryListingSource(const []))(shelf.Request('GET', Uri.parse('https://x$path'))));

void main() {
  test('assetlinks.json names the app id and release certificate', () async {
    final r = await get(withStoreIds(), '/.well-known/assetlinks.json');
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'application/json');
    final links = jsonDecode(await r.readAsString()) as List;
    final target = (links.single as Map)['target'] as Map;
    expect(target['package_name'], 'ke.co.realtimeestates.app');
    expect(target['sha256_cert_fingerprints'], [fingerprint]);
  });

  test('apple-app-site-association covers listing, area and agent pages', () async {
    final r = await get(withStoreIds(), '/.well-known/apple-app-site-association');
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'application/json');
    final details = ((jsonDecode(await r.readAsString()) as Map)['applinks'] as Map)['details'] as List;
    final d = details.single as Map;
    expect(d['appIDs'], ['ABCDE12345.ke.co.realtimeestates.app']);
    expect(d['components'], [
      {'/': '/listing/*'},
      {'/': '/area/*'},
      {'/': '/agent/*'},
    ]);
  });

  test('before the store accounts exist, both files are valid but claim nothing', () async {
    final t = TenantConfig.fromJson(tenantJson());
    expect(jsonDecode(await (await get(t, '/.well-known/assetlinks.json')).readAsString()), isEmpty);
    expect(jsonDecode(await (await get(t, '/.well-known/apple-app-site-association')).readAsString()), {
      'applinks': {'details': []},
    });
  });
}
