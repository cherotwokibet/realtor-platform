import 'package:realtor_core/realtor_core.dart';

/// Paths on the share domain that the installed app opens instead of the
/// browser (P3-s07). The app's router has the same routes.
const appLinkPaths = ['/listing/', '/area/', '/agent/'];

/// `/.well-known/assetlinks.json` for Android App Links. Empty until the
/// tenant has release certificate fingerprints, so nothing verifies early.
List<Map<String, Object?>> assetLinks(TenantConfig t) => [
      if (t.androidCertSha256.isNotEmpty)
        {
          'relation': ['delegate_permission/common.handle_all_urls'],
          'target': {'namespace': 'android_app', 'package_name': t.androidId, 'sha256_cert_fingerprints': t.androidCertSha256},
        },
    ];

/// `/.well-known/apple-app-site-association` for iOS Universal Links.
/// No details until the tenant has an Apple Team ID.
Map<String, Object?> appleAppSiteAssociation(TenantConfig t) => {
      'applinks': {
        'details': [
          if (t.appleTeamId != null)
            {
              'appIDs': ['${t.appleTeamId}.${t.iosId}'],
              'components': [for (final p in appLinkPaths) {'/': '$p*'}],
            },
        ],
      },
    };
