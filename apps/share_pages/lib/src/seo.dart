import 'dart:convert';

import 'package:realtor_core/realtor_core.dart';

import 'listing.dart';

/// URLs and structured data for one listing page. Pure: no rendering here.
class ListingSeo {
  ListingSeo(this.tenant, this.listing);
  final TenantConfig tenant;
  final ShareListing listing;

  String get canonical => 'https://${tenant.shareDomain}/listing/${listing.slug}';

  /// The Flutter app opens the same path (path URLs, P3-s01).
  String get appUrl => 'https://${tenant.appDomain}/listing/${listing.slug}';

  String get _period => switch (listing.purpose) { Purpose.rent => ' a month', Purpose.shortStay => ' a night', Purpose.sale => '' };

  String get title => '${listing.title} · ${formatKes(listing.priceKES)}$_period · ${tenant.name}';

  String get description {
    final l = listing;
    final rooms = l.beds == 0 ? _type(l.type) : '${l.beds} bedroom ${_type(l.type).toLowerCase()}';
    final where = [if (l.estate != null) l.estate!, placeName(l.area)].join(', ');
    final deposit = l.depositMonths == null ? '' : ' Deposit ${l.depositMonths} month${l.depositMonths == 1 ? '' : 's'}.';
    final verified = l.verified ? ' Verified by ${tenant.name}.' : '';
    return '$rooms ${_purposeWords(l.purpose)} in $where for ${formatKes(l.priceKES)}$_period.$deposit$verified';
  }

  /// Public URL of a Storage object in the tenant's prod media bucket.
  String mediaUrl(String path) {
    final bucket = '${tenant.firebaseProjects[FirebaseEnv.prod]}-media';
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(path)}?alt=media';
  }

  /// First photo (full variant) or the tenant's default share image.
  String get ogImage => listing.photos.isEmpty ? 'https://${tenant.appDomain}/og.png' : mediaUrl(listing.photos.first.full);

  Map<String, Object?> get jsonLd => {
        '@context': 'https://schema.org',
        '@type': 'RealEstateListing',
        'name': listing.title,
        'description': description,
        'url': canonical,
        'image': [for (final p in listing.photos) mediaUrl(p.full)],
        if (listing.updatedAt != null) 'dateModified': listing.updatedAt!.toUtc().toIso8601String(),
        'offers': {
          '@type': 'Offer',
          'price': listing.priceKES,
          'priceCurrency': 'KES',
          'businessFunction': listing.purpose == Purpose.sale ? 'http://purl.org/goodrelations/v1#Sell' : 'http://purl.org/goodrelations/v1#LeaseOut',
          'availability': 'https://schema.org/InStock',
          'seller': {'@type': 'RealEstateAgent', 'name': tenant.name, 'url': 'https://${tenant.shareDomain}/'},
        },
        'about': {
          '@type': listing.type == 'land' ? 'Landform' : 'Accommodation',
          if (listing.type != 'land') 'numberOfBedrooms': listing.beds,
          if (listing.type != 'land') 'numberOfBathroomsTotal': listing.baths,
          'address': {'@type': 'PostalAddress', 'addressLocality': placeName(listing.area), 'addressCountry': 'KE'},
          'geo': {'@type': 'GeoCoordinates', 'latitude': listing.lat, 'longitude': listing.lng},
        },
      };

  /// JSON-LD safe to embed in a `<script>` tag: every `<` is written as the
  /// JSON escape `\u003c`, so listing text can never close the script.
  String get jsonLdScript =>
      '<script type="application/ld+json">${jsonEncode(jsonLd).replaceAll('<', '\\u003c')}</script>';

  static String _type(String t) => '${t[0].toUpperCase()}${t.substring(1).replaceAll('-', ' ')}';
  /// "south-b" -> "South B".
  static String placeName(String slug) =>
      slug.split('-').map((w) => w.length <= 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  static String _purposeWords(Purpose p) => switch (p) { Purpose.rent => 'to rent', Purpose.sale => 'for sale', Purpose.shortStay => 'for short stays' };
}
