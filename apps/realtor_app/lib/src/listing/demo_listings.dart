import 'package:realtor_core/realtor_core.dart';

import '../search/demo_search.dart';
import '../search/purpose.dart';

const _agents = [
  ListingAgent(id: 'agent-wanjiku', name: 'Wanjiku Mwangi', phone: '+254700000101', whatsapp: '+254700000101'),
  ListingAgent(id: 'agent-otieno', name: 'Brian Otieno', phone: '+254700000102', whatsapp: '+254700000102'),
  ListingAgent(id: 'agent-achieng', name: 'Achieng Odhiambo', phone: '+254700000103', whatsapp: '+254700000103'),
];

/// Listing details for the demo listings, until the app reads Firestore.
class DemoListingRepository implements ListingRepository {
  @override
  Future<ListingDetail?> bySlug(String slug) async {
    for (final (i, l) in demoListings.indexed) {
      if (l.slug == slug) {
        return ListingDetail(
          summary: l,
          depositMonths: l.purpose == Purpose.rent ? (l.type == 'hostel' ? 1 : 2) : null,
          agent: _agents[i % _agents.length],
        );
      }
    }
    return null;
  }

  @override
  Future<AreaGuide?> area(String slug) async {
    final here = demoListings.where((l) => l.area == slug).toList();
    if (here.isEmpty) return null;
    final rents = [for (final l in here) if (l.purpose == Purpose.rent) l.priceKES]..sort();
    return AreaGuide(
      slug: slug,
      name: areaName(slug),
      county: 'Nairobi',
      lat: here.first.lat,
      lng: here.first.lng,
      guide: 'A demo guide to ${areaName(slug)}.',
      medianRentKES: rents.length >= 3 ? rents[rents.length ~/ 2] : null,
      listings: here.length,
    );
  }

  @override
  Future<AgentProfile?> agent(String id) async {
    final a = _agents.where((a) => a.id == id).firstOrNull;
    return a == null
        ? null
        : AgentProfile(id: a.id, name: a.name, earbNo: 'EARB/DEMO', phone: a.phone, whatsapp: a.whatsapp, languages: const ['en', 'sw'], responseMins: 25);
  }

  @override
  Future<List<ListingSummary>> live({String? area, String? agentId, int limit = 30}) async => [
        for (final (i, l) in demoListings.indexed)
          if ((area == null || l.area == area) && (agentId == null || _agents[i % _agents.length].id == agentId)) l,
      ].take(limit).toList();
}

/// Keeps leads in memory until the app calls the Functions. Nothing leaves
/// the phone, so no personal data is stored anywhere.
class DemoLeadRepository implements LeadRepository {
  final enquiries = <Map<String, String?>>[];
  final taps = <String>[];
  final viewings = <Map<String, String>>[];

  @override
  Future<void> enquire({required String listingId, required String phone, String? name, String? message}) async =>
      enquiries.add({'listingId': listingId, 'phone': phone, 'name': name, 'message': message});

  /// Demo: times listed here are taken; every other time is free.
  final taken = <String>{};

  @override
  Future<List<String>?> openTimes({required String listingId, required String day}) async =>
      [for (final t in viewingTimes) if (!taken.contains('$day $t')) t];

  @override
  Future<void> logTap({required String listingId, required String channel}) async => taps.add('$listingId/$channel');

  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone}) async =>
      viewings.add({'listingId': listingId, 'slot': slot, 'name': name, 'phone': phone});
}
