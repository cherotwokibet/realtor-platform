import 'agent_profile.dart';
import 'area_guide.dart';
import 'listing_search.dart';
import 'off_plan_project.dart';

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
    this.viewingFeeKES,
    this.photos = const [],
    this.videos = const [],
    this.agent,
    this.description = '',
  });
  final ListingSummary summary;
  final String? estate;

  /// The agent's text (P7-s02); may be empty.
  final String description;
  final int? depositMonths;

  /// The listing's viewing fee (P6-s01), paid by M-Pesa after booking; null or 0: free.
  final int? viewingFeeKES;

  /// Media-pipeline `card` variant URLs, in order.
  final List<String> photos;

  /// Walk-through videos (P2-s04), after the photos.
  final List<ListingVideo> videos;

  /// Null when the agent is inactive; the realtor's own numbers are used.
  final ListingAgent? agent;
}

/// A listing video: the HLS playlist (phones), a progressive MP4 for
/// browsers without HLS (null for videos made before it existed), a poster.
class ListingVideo {
  const ListingVideo({required this.hls, this.mp4, required this.poster});
  final String hls, poster;
  final String? mp4;
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

  /// Every area guide, for recognising area names in typed searches (P7-s01).
  Future<List<AreaGuide>> areas();

  /// Published off-plan projects (P5-s06), cheapest first.
  Future<List<OffPlanProject>> projects();

  /// A published off-plan project, or null.
  Future<OffPlanProject?> project(String slug);
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

/// A booked viewing (`bookViewing`'s answer): its id, and the fee the
/// Functions set for it (0 when free or M-Pesa is off).
typedef BookedViewing = ({String viewingId, int feeKES});

/// The lead Functions the app calls (D7: clients never write leads).
abstract interface class LeadRepository {
  /// `createLead`, channel `form`, with the consent tick.
  Future<void> enquire({required String listingId, required String phone, String? name, String? message});

  /// `logContactTap`: counts a call or WhatsApp tap, no personal data (D13).
  Future<void> logTap({required String listingId, required String channel});

  /// `logRecommendation`: counts "Similar homes" under [listingId] being
  /// `shown`, or one of them `opened` (P7-s04). Counts only.
  Future<void> logRecommendation({required String listingId, required String event});

  /// `openSlots`: the times still free on [day] (`2026-10-30`), as in
  /// `viewingTimes`; null when they can't be had (show every time then).
  Future<List<String>?> openTimes({required String listingId, required String day});

  /// `bookViewing`; [slot] as `viewingSlot` builds it.
  Future<BookedViewing> bookViewing({required String listingId, required String slot, required String name, required String phone});

  /// `payments-startViewingPayment` (P6-s01): M-Pesa asks [phone] to pay the
  /// viewing's fee. The amount is the viewing's own; the app never sends one.
  Future<void> payViewingFee({required String viewingId, required String phone});
}
