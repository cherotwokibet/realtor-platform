import 'agent_profile.dart';
import 'area_guide.dart';
import 'listing_search.dart';

/// The agent shown on a listing: their business lines, which the app shows
/// on every listing.
class ListingAgent {
  const ListingAgent({required this.id, required this.name, required this.phone, required this.whatsapp});
  final String id, name, phone, whatsapp;
}

/// Everything the listing screen shows: the search summary plus the facts
/// only the listing document has.
class ListingDetail {
  const ListingDetail({
    required this.summary,
    this.estate,
    this.depositMonths,
    this.photos = const [],
    this.agent,
  });
  final ListingSummary summary;
  final String? estate;
  final int? depositMonths;

  /// Media-pipeline `card` variant URLs, in order.
  final List<String> photos;

  /// Null when the agent is inactive; the realtor's own numbers are used.
  final ListingAgent? agent;
}

/// Where listing details come from: Firestore once the app has Firebase,
/// demo data until then, fakes in tests.
abstract interface class ListingRepository {
  /// A live listing, or null.
  Future<ListingDetail?> bySlug(String slug);

  /// An area's guide, or null.
  Future<AreaGuide?> area(String slug);

  /// An active agent's public profile, or null.
  Future<AgentProfile?> agent(String id);

  /// Live listings in an area or by an agent, newest first.
  Future<List<ListingSummary>> live({String? area, String? agentId, int limit = 30});
}

/// A lead call the Functions refused or could not take.
class LeadException implements Exception {
  LeadException(this.code, this.message);

  /// Callable status, e.g. `already-exists`, `invalid-argument`, `unavailable`.
  final String code;
  final String message;

  @override
  String toString() => 'LeadException($code: $message)';
}

/// The lead Functions the app calls (D7: clients never write leads).
abstract interface class LeadRepository {
  /// `createLead`, channel `form`, with the consent tick.
  Future<void> enquire({required String listingId, required String phone, String? name, String? message});

  /// `logContactTap`: counts a call or WhatsApp tap, no personal data (D13).
  Future<void> logTap({required String listingId, required String channel});

  /// `openSlots`: the times still free on [day] (`2026-10-30`), as in
  /// `viewingTimes`; null when they can't be had (show every time then).
  Future<List<String>?> openTimes({required String listingId, required String day});

  /// `bookViewing`; [slot] as `viewingSlot` builds it.
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone});
}
