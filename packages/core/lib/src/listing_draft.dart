/// A listing as staff create or edit it in the admin (P5-s02), sent to the
/// `submitListing` Function. [problems] mirrors the Function's checks so the
/// form can say what to fix before a round trip; the Function still decides.
library;

import 'listing_filters.dart';

/// An area to pick in the form, with its centre for a first map pin.
typedef AreaOption = ({String slug, String name, double lat, double lng});

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
const _maxKes = 10000000000;

class ListingDraft {
  const ListingDraft({
    this.listingId,
    this.title = '',
    this.purpose = 'rent',
    this.type = 'apartment',
    this.beds = 1,
    this.baths = 1,
    this.priceKES = 0,
    this.depositMonths,
    this.serviceChargeKES,
    this.viewingFeeKES,
    this.lat = 0,
    this.lng = 0,
    this.area = '',
    this.estate,
    this.description = '',
    this.amenities = const [],
    this.agentId,
  });

  /// Null for a new listing.
  final String? listingId;
  final String title, purpose, type, area;
  final int beds, baths, priceKES;
  final int? depositMonths, serviceChargeKES;

  /// Paid by M-Pesa after booking a viewing (P6-s01); null or 0: free.
  final int? viewingFeeKES;
  final double lat, lng;
  final String? estate;

  /// The listing's text (P7-s02); may be empty.
  final String description;
  final List<String> amenities;

  /// Who it is listed for; managers choose, an agent is always themself.
  final String? agentId;

  /// From a `listings/{id}` document.
  factory ListingDraft.fromDoc(String id, Map<String, Object?> d) {
    final geo = d['geo'] is Map ? d['geo']! as Map : const {};
    int? optInt(Object? v) => (v as num?)?.toInt();
    return ListingDraft(
      listingId: id,
      title: d['title'] as String? ?? '',
      purpose: d['purpose'] as String? ?? 'rent',
      type: d['type'] as String? ?? 'apartment',
      beds: optInt(d['beds']) ?? 0,
      baths: optInt(d['baths']) ?? 0,
      priceKES: optInt(d['priceKES']) ?? 0,
      depositMonths: optInt(d['depositMonths']),
      serviceChargeKES: optInt(d['serviceChargeKES']),
      viewingFeeKES: optInt(d['viewingFeeKES']),
      lat: ((geo['lat'] ?? d['lat']) as num?)?.toDouble() ?? 0,
      lng: ((geo['lng'] ?? d['lng']) as num?)?.toDouble() ?? 0,
      area: d['area'] as String? ?? '',
      estate: d['estate'] as String?,
      description: d['description'] as String? ?? '',
      amenities: [for (final a in (d['amenities'] as List<Object?>?) ?? const []) '$a'],
      agentId: d['agentId'] as String?,
    );
  }

  ListingDraft copyWith({
    String? title,
    String? purpose,
    String? type,
    int? beds,
    int? baths,
    int? priceKES,
    int? Function()? depositMonths,
    int? Function()? serviceChargeKES,
    int? Function()? viewingFeeKES,
    double? lat,
    double? lng,
    String? area,
    String? Function()? estate,
    String? description,
    List<String>? amenities,
    String? agentId,
  }) =>
      ListingDraft(
        listingId: listingId,
        title: title ?? this.title,
        purpose: purpose ?? this.purpose,
        type: type ?? this.type,
        beds: beds ?? this.beds,
        baths: baths ?? this.baths,
        priceKES: priceKES ?? this.priceKES,
        depositMonths: depositMonths == null ? this.depositMonths : depositMonths(),
        serviceChargeKES: serviceChargeKES == null ? this.serviceChargeKES : serviceChargeKES(),
        viewingFeeKES: viewingFeeKES == null ? this.viewingFeeKES : viewingFeeKES(),
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        area: area ?? this.area,
        estate: estate == null ? this.estate : estate(),
        description: description ?? this.description,
        amenities: amenities ?? this.amenities,
        agentId: agentId ?? this.agentId,
      );

  /// What is wrong, by field; empty when the Function should accept it.
  Map<String, String> problems() => {
        if (title.trim().length < 5 || title.trim().length > 120) 'title': 'Use 5 to 120 characters.',
        if (!Purpose.values.any((p) => p.value == purpose)) 'purpose': 'Pick rent, sale or short stay.',
        if (!listingTypeSlugs.containsKey(type)) 'type': 'Pick a type.',
        if (beds < 0 || beds > 20) 'beds': '0 to 20.',
        if (baths < 0 || baths > 20) 'baths': '0 to 20.',
        if (priceKES <= 0 || priceKES > _maxKes) 'priceKES': 'Enter the price in whole shillings.',
        if (depositMonths != null && (depositMonths! < 0 || depositMonths! > 12)) 'depositMonths': '0 to 12 months.',
        if (serviceChargeKES != null && (serviceChargeKES! < 0 || serviceChargeKES! > _maxKes)) 'serviceChargeKES': 'Whole shillings.',
        if (viewingFeeKES != null && (viewingFeeKES! < 0 || viewingFeeKES! > maxViewingFeeKES)) 'viewingFeeKES': 'KES 0 to 10,000.',
        if (!_slug.hasMatch(area)) 'area': 'Pick an area.',
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180 || (lat == 0 && lng == 0)) 'location': 'Set the map position.',
        if ((estate ?? '').length > 80) 'estate': 'Under 80 characters.',
        if (description.trim().length > 3000) 'description': 'Under 3,000 characters.',
        if (amenities.length > 40 || amenities.any((a) => a.length > 40)) 'amenities': 'Up to 40, each under 40 characters.',
      };

  /// The `submitListing` input. Media is left out, so the listing keeps its
  /// photos and videos as they are.
  Map<String, Object?> toCallable() => {
        if (listingId != null) 'listingId': listingId,
        'title': title.trim(),
        'purpose': purpose,
        'type': type,
        'beds': beds,
        'baths': baths,
        'priceKES': priceKES,
        if (depositMonths != null) 'depositMonths': depositMonths,
        if (serviceChargeKES != null) 'serviceChargeKES': serviceChargeKES,
        if (viewingFeeKES != null) 'viewingFeeKES': viewingFeeKES,
        'lat': lat,
        'lng': lng,
        'area': area,
        if ((estate ?? '').trim().isNotEmpty) 'estate': estate!.trim(),
        if (description.trim().isNotEmpty) 'description': description.trim(),
        'amenities': [for (final a in amenities) if (a.trim().isNotEmpty) a.trim()],
        if (agentId != null) 'agentId': agentId,
      };
}

/// Same ceiling as the Functions' schema: a viewing fee is a token, not a deposit.
const maxViewingFeeKES = 10000;
