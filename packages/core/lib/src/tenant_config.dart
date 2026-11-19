// Typed view of tenants/<id>.json. The JSON Schema in tenants/schema is the
// source of truth; CI validates every tenant file against it before this
// parser ever sees one, so the parser stays strict and simple.

import 'listing_filters.dart';

/// Thrown when a tenant file is missing a field or has the wrong type.
class TenantConfigException implements Exception {
  TenantConfigException(this.message);
  final String message;
  @override
  String toString() => 'TenantConfigException: $message';
}

typedef Json = Map<String, Object?>;

T _req<T>(Json j, String key, String path) {
  final v = j[key];
  if (v is! T) {
    throw TenantConfigException('$path.$key must be ${T.toString()}, got ${v.runtimeType}');
  }
  return v;
}

Json _obj(Json j, String key, String path) => _req<Map<String, Object?>>(j, key, path);

/// Parses "#RRGGBB" into an opaque ARGB int (0xFFRRGGBB).
int parseHexColor(String hex) {
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(hex);
  if (m == null) throw TenantConfigException('bad colour "$hex", expected #RRGGBB');
  return 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

class BrandColors {
  const BrandColors({
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.ink,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
    required this.surface,
    required this.background,
    required this.surfaceAlt,
    required this.info,
    required this.success,
    required this.error,
  });

  /// All values are ARGB ints, ready for Flutter's `Color(int)`.
  final int primary, onPrimary, primarySoft, accent, onAccent, accentText;
  final int ink, text, textMuted, border, borderStrong;
  final int surface, background, surfaceAlt, info, success, error;

  factory BrandColors.fromJson(Json j) {
    int c(String k) => parseHexColor(_req<String>(j, k, 'brand.colors'));
    return BrandColors(
      primary: c('primary'),
      onPrimary: c('onPrimary'),
      primarySoft: c('primarySoft'),
      accent: c('accent'),
      onAccent: c('onAccent'),
      accentText: c('accentText'),
      ink: c('ink'),
      text: c('text'),
      textMuted: c('textMuted'),
      border: c('border'),
      borderStrong: c('borderStrong'),
      surface: c('surface'),
      background: c('background'),
      surfaceAlt: c('surfaceAlt'),
      info: c('info'),
      success: c('success'),
      error: c('error'),
    );
  }
}

class TypeScale {
  const TypeScale({
    required this.caption,
    required this.body,
    required this.bodyLarge,
    required this.title,
    required this.headline,
    required this.display,
  });
  final double caption, body, bodyLarge, title, headline, display;

  factory TypeScale.fromJson(Json j) {
    double n(String k) => _req<num>(j, k, 'brand.typeScale').toDouble();
    return TypeScale(
      caption: n('caption'),
      body: n('body'),
      bodyLarge: n('bodyLarge'),
      title: n('title'),
      headline: n('headline'),
      display: n('display'),
    );
  }
}

class Brand {
  const Brand({
    required this.logo,
    required this.logoOnDark,
    this.logoHorizontal,
    required this.appIcon,
    required this.colors,
    required this.displayFont,
    required this.bodyFont,
    required this.typeScale,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusPill,
    required this.spacingBase,
  });

  /// Repo-relative asset paths, e.g. `brand/<id>/logo-stacked.svg`.
  final String logo;
  final String? logoOnDark;

  /// The wide lockup for page headers; null falls back to [logo].
  final String? logoHorizontal;
  final String appIcon;
  final BrandColors colors;
  final String displayFont, bodyFont;
  final TypeScale typeScale;
  final double radiusSm, radiusMd, radiusPill, spacingBase;

  factory Brand.fromJson(Json j) {
    const p = 'brand';
    final logo = _obj(j, 'logo', p);
    final fonts = _obj(j, 'fonts', p);
    final radius = _obj(j, 'radius', p);
    return Brand(
      logo: _req<String>(logo, 'primary', '$p.logo'),
      logoOnDark: logo['onDark'] as String?,
      logoHorizontal: logo['horizontal'] as String?,
      appIcon: _req<String>(j, 'appIcon', p),
      colors: BrandColors.fromJson(_obj(j, 'colors', p)),
      displayFont: _req<String>(fonts, 'display', '$p.fonts'),
      bodyFont: _req<String>(fonts, 'body', '$p.fonts'),
      typeScale: TypeScale.fromJson(_obj(j, 'typeScale', p)),
      radiusSm: _req<num>(radius, 'sm', '$p.radius').toDouble(),
      radiusMd: _req<num>(radius, 'md', '$p.radius').toDouble(),
      radiusPill: _req<num>(radius, 'pill', '$p.radius').toDouble(),
      spacingBase: _req<num>(j, 'spacingBase', p).toDouble(),
    );
  }
}

/// One switch in the tenant file's `features` block. Names match the JSON keys.
enum Feature { sale, rent, shortStay, offPlan, mpesa, ads, aiSearch, chat }

/// Feature switches. A realtor is upgraded by flipping one and redeploying.
class Features {
  const Features({
    required this.sale,
    required this.rent,
    required this.shortStay,
    required this.offPlan,
    required this.mpesa,
    required this.ads,
    required this.aiSearch,
    required this.chat,
  });
  final bool sale, rent, shortStay, offPlan, mpesa, ads, aiSearch, chat;

  bool isOn(Feature f) => switch (f) {
        Feature.sale => sale,
        Feature.rent => rent,
        Feature.shortStay => shortStay,
        Feature.offPlan => offPlan,
        Feature.mpesa => mpesa,
        Feature.ads => ads,
        Feature.aiSearch => aiSearch,
        Feature.chat => chat,
      };

  /// Whether listings for [purpose] are offered: rent and sale have their
  /// own switch, short stays follow [shortStay].
  bool allowsPurpose(Purpose purpose) => switch (purpose) {
        Purpose.rent => rent,
        Purpose.sale => sale,
        Purpose.shortStay => shortStay,
      };

  /// A copy with some switches changed (tests, admin previews).
  Features copyWith(Map<Feature, bool> changes) {
    bool v(Feature f) => changes[f] ?? isOn(f);
    return Features(
      sale: v(Feature.sale),
      rent: v(Feature.rent),
      shortStay: v(Feature.shortStay),
      offPlan: v(Feature.offPlan),
      mpesa: v(Feature.mpesa),
      ads: v(Feature.ads),
      aiSearch: v(Feature.aiSearch),
      chat: v(Feature.chat),
    );
  }

  factory Features.fromJson(Json j) {
    bool b(String k) => _req<bool>(j, k, 'features');
    return Features(
      sale: b('sale'),
      rent: b('rent'),
      shortStay: b('shortStay'),
      offPlan: b('offPlan'),
      mpesa: b('mpesa'),
      ads: b('ads'),
      aiSearch: b('aiSearch'),
      chat: b('chat'),
    );
  }
}

enum FirebaseEnv { dev, stage, prod }

/// One photo band on the home page: the hero behind the search, or the
/// promotion under it. The words are the realtor's (tenant file `home`).
/// [imageCount] is how many photos the tenant file names (`images`, or one
/// `image`); `tenant prepare` bundles them under fixed, numbered names, and
/// the band falls back to the brand colour when there are none.
class HomeBand {
  const HomeBand({required this.title, this.text, this.imageCount = 0});
  final String title;
  final String? text;
  final int imageCount;

  bool get hasImage => imageCount > 0;

  /// Matches the tenant schema's limit.
  static const maxImages = 8;

  static HomeBand? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final images = j['images'] is List ? (j['images'] as List).length : (j['image'] is String ? 1 : 0);
    return HomeBand(
      title: _req<String>(j, 'title', 'home'),
      text: j['text'] as String?,
      imageCount: images > maxImages ? maxImages : images,
    );
  }
}

/// What the realtor says on the home page; both parts are optional.
class HomeContent {
  const HomeContent({this.hero, this.banner});
  final HomeBand? hero, banner;

  factory HomeContent.fromJson(Object? j) =>
      j is Map<String, Object?> ? HomeContent(hero: HomeBand.fromJson(j['hero']), banner: HomeBand.fromJson(j['banner'])) : const HomeContent();
}

class TenantConfig {
  const TenantConfig({
    required this.id,
    required this.name,
    required this.tagline,
    required this.earbNo,
    required this.brand,
    required this.shareDomain,
    required this.appDomain,
    required this.adminDomain,
    required this.androidId,
    required this.iosId,
    this.androidCertSha256 = const [],
    this.appleTeamId,
    this.googlePlayUrl,
    this.appStoreUrl,
    required this.firebaseProjects,
    required this.firebaseRegion,
    required this.phone,
    required this.whatsapp,
    required this.email,
    required this.defaultLocale,
    required this.extraLocales,
    required this.currency,
    required this.features,
    this.home = const HomeContent(),
    this.mapTiles = defaultMapTiles,
    this.mapAttribution = defaultMapAttribution,
  });

  final String id, name;
  final String? tagline, earbNo;
  final Brand brand;
  final String shareDomain, appDomain, adminDomain;
  final String androidId, iosId;

  /// Release certificate fingerprints and Apple Team ID for App Links and
  /// Universal Links; empty / null until the store accounts exist.
  final List<String> androidCertSha256;
  final String? appleTeamId;

  /// The app's store pages, for the Download the app badges; null until it is there.
  final String? googlePlayUrl, appStoreUrl;
  final Map<FirebaseEnv, String> firebaseProjects;
  final String firebaseRegion;

  /// 'TBC' until the realtor supplies them; check [hasContactNumbers].
  final String phone, whatsapp, email;
  final String defaultLocale;
  final List<String> extraLocales;
  final String currency;
  final Features features;

  /// Home page words and photos (tenant file `home`).
  final HomeContent home;

  /// Map search (P3-s04): a raster tile URL template ({z}/{x}/{y}) and the
  /// credit the provider requires. OpenStreetMap unless the tenant file sets
  /// `map`, so a realtor can move to MapTiler, Stadia or similar without code.
  final String mapTiles, mapAttribution;

  bool get hasContactNumbers => phone != 'TBC' && whatsapp != 'TBC';

  /// The same tenant with other feature switches.
  TenantConfig withFeatures(Features f) => TenantConfig(
        id: id,
        name: name,
        tagline: tagline,
        earbNo: earbNo,
        brand: brand,
        shareDomain: shareDomain,
        appDomain: appDomain,
        adminDomain: adminDomain,
        androidId: androidId,
        iosId: iosId,
        androidCertSha256: androidCertSha256,
        appleTeamId: appleTeamId,
        googlePlayUrl: googlePlayUrl,
        appStoreUrl: appStoreUrl,
        firebaseProjects: firebaseProjects,
        firebaseRegion: firebaseRegion,
        phone: phone,
        whatsapp: whatsapp,
        email: email,
        defaultLocale: defaultLocale,
        extraLocales: extraLocales,
        currency: currency,
        features: f,
        home: home,
        mapTiles: mapTiles,
        mapAttribution: mapAttribution,
      );

  /// WhatsApp deep link with a prefilled message, or null until a number exists.
  Uri? whatsappLink(String message) => whatsapp == 'TBC'
      ? null
      : Uri.https('wa.me', '/${whatsapp.replaceAll('+', '')}', {'text': message});

  factory TenantConfig.fromJson(Json j) {
    const p = 'tenant';
    final version = j['schemaVersion'];
    if (version != 1) throw TenantConfigException('unsupported schemaVersion $version');
    final domains = _obj(j, 'domains', p);
    final apps = _obj(j, 'apps', p);
    final fb = _obj(j, 'firebase', p);
    final projects = _obj(fb, 'projects', 'firebase');
    final contact = _obj(j, 'contact', p);
    final locale = _obj(j, 'locale', p);
    return TenantConfig(
      id: _req<String>(j, 'id', p),
      name: _req<String>(j, 'name', p),
      tagline: j['tagline'] as String?,
      earbNo: j['earbNo'] as String?,
      brand: Brand.fromJson(_obj(j, 'brand', p)),
      shareDomain: _req<String>(domains, 'share', 'domains'),
      appDomain: _req<String>(domains, 'app', 'domains'),
      adminDomain: _req<String>(domains, 'admin', 'domains'),
      androidId: _req<String>(apps, 'androidId', 'apps'),
      iosId: _req<String>(apps, 'iosId', 'apps'),
      androidCertSha256: ((apps['androidCertSha256'] as List<Object?>?) ?? const []).cast<String>(),
      appleTeamId: apps['appleTeamId'] as String?,
      googlePlayUrl: apps['googlePlayUrl'] as String?,
      appStoreUrl: apps['appStoreUrl'] as String?,
      firebaseProjects: {
        for (final e in FirebaseEnv.values) e: _req<String>(projects, e.name, 'firebase.projects'),
      },
      firebaseRegion: _req<String>(fb, 'region', 'firebase'),
      phone: _req<String>(contact, 'phone', 'contact'),
      whatsapp: _req<String>(contact, 'whatsapp', 'contact'),
      email: _req<String>(contact, 'email', 'contact'),
      defaultLocale: _req<String>(locale, 'default', 'locale'),
      extraLocales: _req<List<Object?>>(locale, 'extra', 'locale').cast<String>(),
      currency: _req<String>(locale, 'currency', 'locale'),
      features: Features.fromJson(_obj(j, 'features', p)),
      home: HomeContent.fromJson(j['home']),
      mapTiles: (j['map'] as Map?)?['tiles'] as String? ?? defaultMapTiles,
      mapAttribution: (j['map'] as Map?)?['attribution'] as String? ?? defaultMapAttribution,
    );
  }
}

/// OpenStreetMap's standard tiles (decided 2 Nov): free, no key. Their usage
/// policy asks for attribution and an identifying User-Agent; a busy tenant
/// should move to a paid tile host via the tenant file's `map` block.
const defaultMapTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const defaultMapAttribution = '© OpenStreetMap contributors';
