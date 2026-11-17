import 'listing_repository.dart' show LeadException;

/// A review shown on a listing: stars, a comment, a first name at most.
/// Only reviews a manager has approved are ever read.
class ListingReview {
  const ListingReview({required this.rating, required this.createdAt, this.comment, this.name, this.afterViewing = false});
  final int rating;
  final DateTime createdAt;
  final String? comment, name;

  /// Left with the link sent after a viewing, rather than by any visitor.
  final bool afterViewing;

  /// [d] as stored, with `createdAt` already a [DateTime] (the Firestore
  /// layer converts its timestamps). Null when it is not a usable review.
  static ListingReview? fromDoc(Map<String, Object?> d) {
    final rating = (d['rating'] as num?)?.toInt();
    final when = d['createdAt'];
    if (rating == null || rating < 1 || rating > 5 || when is! DateTime) return null;
    return ListingReview(
      rating: rating,
      createdAt: when,
      comment: d['comment'] as String?,
      name: d['name'] as String?,
      afterViewing: d['kind'] != 'listing',
    );
  }
}

/// The average of [reviews], to one decimal; null when there are none.
double? averageRating(List<ListingReview> reviews) =>
    reviews.isEmpty ? null : (reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length * 10).round() / 10;

/// Where a listing's reviews come from, and where a signed-in visitor's goes.
abstract interface class ListingReviews {
  /// Approved reviews of the listing, newest first.
  Future<List<ListingReview>> forListing(String listingId);

  /// `submitListingReview`: waits for a manager before it shows. Throws
  /// [LeadException] (`already-exists`, `unauthenticated`, ...).
  Future<void> submit({required String listingId, required int rating, required String comment, String? name});
}
