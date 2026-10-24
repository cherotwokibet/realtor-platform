import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_ui/realtor_ui.dart';

/// Serves assets from a map, like the bundle `tenant prepare` produces.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, List<int>> files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers each family from the manifest', () async {
    final files = [('Poppins', 400, 'Regular'), ('Poppins', 600, 'SemiBold'), ('Inter', 400, 'Regular')];
    final manifest = [
      for (final (family, w, name) in files)
        {'family': family, 'weight': w, 'asset': 'assets/tenant/fonts/$family-$name.ttf'},
    ];
    final bundle = _MapBundle({
      tenantFontsManifestPath: utf8.encode(jsonEncode(manifest)),
      for (final (family, _, name) in files)
        'assets/tenant/fonts/$family-$name.ttf': File('../../fonts/$family/$family-$name.ttf').readAsBytesSync(),
    });
    expect(await loadTenantFonts(bundle), {'Poppins', 'Inter'});
  });

  test('no manifest means platform fonts, not a crash', () async {
    expect(await readTenantFonts(_MapBundle({})), isEmpty);
    expect(await loadTenantFonts(_MapBundle({})), isEmpty);
  });
}
