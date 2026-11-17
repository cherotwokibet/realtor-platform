import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('a review document becomes a review; bad ones are skipped', () {
    final r = ListingReview.fromDoc({'rating': 4, 'createdAt': DateTime.utc(2026, 11, 1), 'comment': 'Quiet street.', 'name': 'Akinyi', 'kind': 'listing'})!;
    expect((r.rating, r.comment, r.name, r.afterViewing), (4, 'Quiet street.', 'Akinyi', false));
    expect(ListingReview.fromDoc({'rating': 5, 'createdAt': DateTime.utc(2026)})!.afterViewing, isTrue);
    expect(ListingReview.fromDoc({'rating': 9, 'createdAt': DateTime.utc(2026)}), isNull);
    expect(ListingReview.fromDoc({'rating': 3}), isNull);
  });

  test('the average is to one decimal, or null', () {
    ListingReview r(int n) => ListingReview(rating: n, createdAt: DateTime.utc(2026));
    expect(averageRating([r(5), r(4), r(4)]), 4.3);
    expect(averageRating(const []), isNull);
  });
}
