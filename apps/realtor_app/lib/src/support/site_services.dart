import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

/// What the site reads and sends beyond homes: the adverts managers run
/// (the Ads page in the admin) and Help & feedback messages.
abstract interface class SiteServices {
  /// Adverts switched on; the caller keeps those in date.
  Future<List<AdRow>> ads();

  /// The public address of an advert's photo.
  String? imageUrl(String path);

  /// `submitFeedback`; throws [FeedbackException] with a reason to show.
  Future<void> sendFeedback({required String kind, required String message, String? name, String? phone, String? email, String? page});
}

class FeedbackException implements Exception {
  FeedbackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Demo: no adverts (the tenant's own banner shows), messages kept in memory.
class DemoSiteServices implements SiteServices {
  final sent = <Map<String, Object?>>[];
  List<AdRow> demoAds = const [];

  @override
  Future<List<AdRow>> ads() async => demoAds;

  @override
  String? imageUrl(String path) => null;

  @override
  Future<void> sendFeedback({required String kind, required String message, String? name, String? phone, String? email, String? page}) async {
    if (message.trim().length < 5) throw FeedbackException('Write a little more (at least 5 characters).');
    sent.add({
      'kind': kind,
      'message': message.trim(),
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (page != null) 'page': page,
    });
  }
}

final siteServicesProvider = Provider<SiteServices>((ref) => DemoSiteServices());

/// The adverts running today, newest first.
final runningAdsProvider = FutureProvider<List<AdRow>>((ref) async {
  final now = DateTime.now();
  try {
    return [
      for (final a in await ref.watch(siteServicesProvider).ads())
        if (a.runningOn(now)) a
    ];
  } on Object {
    return const []; // no adverts beats a broken page
  }
});
