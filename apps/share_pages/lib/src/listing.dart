import 'package:realtor_core/realtor_core.dart';

/// What a share page needs about one live listing (read from Firestore).
class ShareListing {
  const ShareListing({
    required this.id,
    required this.slug,
    required this.title,
    required this.purpose,
    required this.type,
    required this.beds,
    required this.baths,
    required this.priceKES,
    required this.area,
    required this.lat,
    required this.lng,
    this.estate,
    this.depositMonths,
    this.amenities = const [],
    this.photos = const [],
    this.verified = false,
    this.updatedAt,
    this.agentId,
    this.description = '',
  });

  final String id, slug, title, type, area;

  /// The agent's text (P7-s02); may be empty.
  final String description;
  final String? agentId;
  final Purpose purpose;
  final int beds, baths, priceKES;
  final int? depositMonths;
  final double lat, lng;
  final String? estate;
  final List<String> amenities;

  /// Storage paths of the media pipeline's `card` / `full` variants.
  final List<({String card, String full})> photos;
  final bool verified;
  final DateTime? updatedAt;
}

/// An area guide (areas/{slug}).
class ShareArea {
  const ShareArea({
    required this.slug,
    required this.name,
    required this.county,
    required this.lat,
    required this.lng,
    this.guide = '',
    this.amenities = const [],
    this.medianRentKES,
  });
  final String slug, name, county, guide;

  /// Nearby places the realtor lists (malls, hospitals, transport).
  final List<String> amenities;
  final double lat, lng;
  final int? medianRentKES;
}

/// An active agent's public profile (agents/{id}). Phone numbers here are
/// the agent's business lines, which the app shows on every listing.
class ShareAgent {
  const ShareAgent({
    required this.id,
    required this.name,
    required this.earbNo,
    required this.phone,
    required this.whatsapp,
    this.languages = const ['en'],
    this.photo,
    this.rating,
    this.responseMins,
  });
  final String id, name, earbNo, phone, whatsapp;
  final List<String> languages;
  final String? photo;
  final double? rating;
  final int? responseMins;
}

/// An approved review (P6-s03): stars, what they wrote, a first name.
typedef ShareReview = ({int rating, String? comment, String? name, DateTime? at});

/// One unit type in an off-plan project (projects/{slug}.units).
typedef ProjectUnit = ({String type, int beds, int? sizeSqm, int fromKES, int available});

/// One payment stage; a project's stages add up to 100%.
typedef PaymentStage = ({String stage, int percent});

/// A published off-plan project (P5-s06), written by managers through the
/// saveProject callable.
class ShareProject {
  const ShareProject({
    required this.slug,
    required this.name,
    required this.developer,
    required this.area,
    required this.summary,
    required this.completion,
    required this.units,
    required this.paymentPlan,
    required this.fromKES,
    this.updatedAt,
  });
  final String slug, name, developer, area, summary;

  /// Expected handover, `YYYY-MM`.
  final String completion;
  final List<ProjectUnit> units;
  final List<PaymentStage> paymentPlan;
  final int fromKES;
  final DateTime? updatedAt;
}

/// One URL in sitemap.xml.
typedef SitemapEntry = ({String path, DateTime? lastModified, Purpose? purpose});

/// Where share pages read from: Firestore in production, fixed lists in
/// tests and local runs.
abstract interface class ListingSource {
  Future<ShareListing?> bySlug(String slug);
  Future<ShareArea?> area(String slug);

  /// Live listings in an area, newest first, at most [limit].
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24});

  /// An active agent, else null.
  Future<ShareAgent?> agent(String id);

  /// An agent's live listings, newest first, at most [limit].
  Future<List<ShareListing>> liveByAgent(String agentId, {int limit = 24});

  /// A published site page (about, privacy, ...), else null.
  Future<({String title, String body, DateTime? updatedAt})?> page(String slug);

  /// Published site pages, for the footer.
  Future<List<({String slug, String title})>> publishedPages();

  /// An agent's approved reviews, newest first, at most [limit].
  Future<List<ShareReview>> reviews(String agentId, {int limit = 5});

  /// The newest live listings, for the home page.
  Future<List<ShareListing>> latestLive({int limit = 12});

  /// Every area, by name.
  Future<List<ShareArea>> areas();

  /// A published off-plan project, else null.
  Future<ShareProject?> project(String slug);

  /// Published off-plan projects, cheapest first.
  Future<List<ShareProject>> publishedProjects();

  /// Every live listing, area, active agent and published project.
  Future<List<SitemapEntry>> sitemapEntries();
}

class InMemoryListingSource implements ListingSource {
  InMemoryListingSource(this.listings,
      {List<ShareArea> areas = const [], this.agents = const [], this.agentReviews = const {}, this.projects = const []})
      : _areas = areas;
  final List<ShareListing> listings;

  /// Published projects.
  final List<ShareProject> projects;

  @override
  Future<ShareProject?> project(String slug) async => projects.where((p) => p.slug == slug).firstOrNull;

  @override
  Future<List<ShareProject>> publishedProjects() async => [...projects]..sort((a, b) => a.fromKES.compareTo(b.fromKES));

  /// Agent id -> approved reviews, newest first.
  final Map<String, List<ShareReview>> agentReviews;

  /// Published site pages by slug.
  Map<String, ({String title, String body})> sitePages = {};

  @override
  Future<({String title, String body, DateTime? updatedAt})?> page(String slug) async =>
      sitePages[slug] == null ? null : (title: sitePages[slug]!.title, body: sitePages[slug]!.body, updatedAt: null);

  @override
  Future<List<({String slug, String title})>> publishedPages() async => [for (final e in sitePages.entries) (slug: e.key, title: e.value.title)];

  @override
  Future<List<ShareReview>> reviews(String agentId, {int limit = 5}) async => [...?agentReviews[agentId]].take(limit).toList();

  final List<ShareArea> _areas;
  final List<ShareAgent> agents;

  @override
  Future<ShareListing?> bySlug(String slug) async {
    for (final l in listings) {
      if (l.slug == slug) return l;
    }
    return null;
  }

  @override
  Future<ShareArea?> area(String slug) async {
    for (final a in _areas) {
      if (a.slug == slug) return a;
    }
    return null;
  }

  @override
  Future<ShareAgent?> agent(String id) async {
    for (final a in agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<List<ShareListing>> liveByAgent(String agentId, {int limit = 24}) async =>
      listings.where((l) => l.agentId == agentId).take(limit).toList();

  @override
  Future<List<ShareListing>> latestLive({int limit = 12}) async => listings.take(limit).toList();

  @override
  Future<List<ShareArea>> areas() async => [..._areas]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24}) async =>
      listings.where((l) => l.area == slug).take(limit).toList();

  @override
  Future<List<SitemapEntry>> sitemapEntries() async => [
        for (final a in _areas) (path: '/area/${a.slug}', lastModified: null, purpose: null),
        for (final a in agents) (path: '/agent/${a.id}', lastModified: null, purpose: null),
        for (final l in listings) (path: '/listing/${l.slug}', lastModified: l.updatedAt, purpose: l.purpose),
        for (final p in projects) (path: '/project/${p.slug}', lastModified: p.updatedAt, purpose: null),
      ];
}

/// Hides what the tenant has switched off: listings for a purpose whose
/// feature is off, and off-plan projects when `offPlan` is off, are not
/// found, not listed, and not in the sitemap.
class FeatureFilteredSource implements ListingSource {
  FeatureFilteredSource(this._inner, this._features);
  final ListingSource _inner;
  final Features _features;

  List<ShareListing> _on(List<ShareListing> ls) => [for (final l in ls) if (_features.allowsPurpose(l.purpose)) l];

  @override
  Future<ShareListing?> bySlug(String slug) async {
    final l = await _inner.bySlug(slug);
    return l != null && _features.allowsPurpose(l.purpose) ? l : null;
  }

  bool get _offPlan => _features.isOn(Feature.offPlan);

  @override
  Future<ShareProject?> project(String slug) async => _offPlan ? _inner.project(slug) : null;

  @override
  Future<List<ShareProject>> publishedProjects() async => _offPlan ? _inner.publishedProjects() : const [];

  @override
  Future<ShareArea?> area(String slug) => _inner.area(slug);

  @override
  Future<ShareAgent?> agent(String id) => _inner.agent(id);

  @override
  Future<List<ShareArea>> areas() => _inner.areas();

  @override
  Future<({String title, String body, DateTime? updatedAt})?> page(String slug) => _inner.page(slug);

  @override
  Future<List<({String slug, String title})>> publishedPages() => _inner.publishedPages();

  @override
  Future<List<ShareReview>> reviews(String agentId, {int limit = 5}) => _inner.reviews(agentId, limit: limit);

  @override
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24}) async => _on(await _inner.liveInArea(slug, limit: limit));

  @override
  Future<List<ShareListing>> liveByAgent(String agentId, {int limit = 24}) async =>
      _on(await _inner.liveByAgent(agentId, limit: limit));

  @override
  Future<List<ShareListing>> latestLive({int limit = 12}) async => _on(await _inner.latestLive(limit: limit));

  @override
  Future<List<SitemapEntry>> sitemapEntries() async => [
        for (final e in await _inner.sitemapEntries())
          if ((e.purpose == null || _features.allowsPurpose(e.purpose!)) && (_offPlan || !e.path.startsWith('/project/'))) e
      ];
}
