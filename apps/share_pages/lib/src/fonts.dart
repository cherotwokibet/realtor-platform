import 'dart:io';

import 'package:realtor_core/realtor_core.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Weights bundled for every family in `fonts/<Family>/` (see fonts/README.md).
const fontWeights = {
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
};

/// `Plus Jakarta Sans` -> `PlusJakartaSans`, the folder and file prefix.
String fontDirName(String family) => family.replaceAll(' ', '');

String _fileName(String family, int weight) =>
    '${fontDirName(family)}-${fontWeights[weight]}.ttf';

/// The tenant's display and body families (one when they are the same).
List<String> tenantFamilies(TenantConfig tenant) =>
    {tenant.brand.displayFont, tenant.brand.bodyFont}.toList();

/// `@font-face` rules for the tenant's families, served from `/fonts/`.
/// `swap` shows text in the system font at once and switches when the file
/// arrives, so a slow 3G connection never waits on a font to read a price.
String fontFaceCss(TenantConfig tenant) => [
  for (final family in tenantFamilies(tenant))
    for (final w in fontWeights.keys)
      '@font-face{font-family:"$family";font-weight:$w;font-style:normal;font-display:swap;'
          'src:url(/fonts/${_fileName(family, w)}) format("truetype")}',
].join('\n');

/// Serves `/fonts/<file>` from [dir] (the repo's `fonts/` folder, copied into
/// the image), only for the tenant's own families. Anything else is a 404, so
/// the route cannot be used to read other files.
shelf.Response serveFont(TenantConfig tenant, String dir, String file) {
  for (final family in tenantFamilies(tenant)) {
    for (final w in fontWeights.keys) {
      if (file != _fileName(family, w)) continue;
      final f = File('$dir/${fontDirName(family)}/$file');
      if (!f.existsSync()) return shelf.Response.notFound('font not bundled');
      return shelf.Response.ok(
        f.openRead(),
        headers: {
          'content-type': 'font/ttf',
          'content-length': '${f.lengthSync()}',
          // Names carry the weight, not a version; a month, and the CDN may keep it.
          'cache-control': 'public, max-age=2592000',
          'access-control-allow-origin': '*',
        },
      );
    }
  }
  return shelf.Response.notFound('not found');
}

/// Path the pages load the tenant's header logo from.
const logoPath = '/logo.svg';

/// Serves [logoPath] from [dir] (`brand/<id>/` copied into the image): the
/// tenant's horizontal logo, or its primary one. Only that one file.
shelf.Response serveLogo(TenantConfig tenant, String dir) {
  final f = File('$dir/${(tenant.brand.logoHorizontal ?? tenant.brand.logo).split('/').last}');
  if (!f.existsSync()) return shelf.Response.notFound('logo not bundled');
  return shelf.Response.ok(
    f.openRead(),
    headers: {
      'content-type': 'image/svg+xml',
      'content-length': '${f.lengthSync()}',
      'cache-control': 'public, max-age=86400',
    },
  );
}
