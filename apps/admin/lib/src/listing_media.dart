import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

/// A file the user picked: its name, bytes and MIME type.
typedef PickedFile = ({String name, Uint8List bytes, String type});

/// The listing's photos and videos as the editor shows them.
class ListingMediaState {
  const ListingMediaState({this.thumbs = const [], this.videos = 0, this.lastError});

  /// Storage paths of each photo's small variant, in listing order.
  final List<String> thumbs;
  final int videos;

  /// Why the last upload was refused (too small, too long, ...), if it was.
  final String? lastError;
}

/// Uploads go to `uploads/...` in the media bucket; the media pipeline
/// (Functions, D6/D15) checks, resizes and adds them to the listing.
abstract interface class ListingMedia {
  Future<ListingMediaState> state(StaffUser who, String listingId);
  Future<void> upload(StaffUser who, String listingId, PickedFile file);

  /// Public URL of a media path, or null where there is none (demo).
  String? url(String path);
}

/// Opens the browser's file chooser.
abstract interface class FilePicker {
  Future<List<PickedFile>> pick({required String accept});
}

/// What storage.rules accept: photos under 20 MB, videos under 200 MB.
const photoTypes = {'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'};
const videoTypes = {'video/mp4', 'video/quicktime', 'video/3gpp'};
const maxPhotoBytes = 20 * 1024 * 1024, maxVideoBytes = 200 * 1024 * 1024;

/// Why [f] can't be uploaded, or null when it can.
String? uploadProblem(PickedFile f) {
  final photo = photoTypes.contains(f.type), video = videoTypes.contains(f.type);
  if (!photo && !video) return '${f.name}: not a photo or video we take (JPEG, PNG, WebP, HEIC, MP4, MOV)';
  if (photo && f.bytes.length >= maxPhotoBytes) return '${f.name}: photos must be under 20 MB';
  if (video && f.bytes.length >= maxVideoBytes) return '${f.name}: videos must be under 200 MB';
  return null;
}

/// `uploads/agents/<agentId>/...` for agents, `uploads/staff/<uid>/...` for
/// managers (storage.rules); a time prefix keeps same-named files apart.
String uploadPath(StaffUser who, String listingId, String fileName, DateTime at) {
  final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  final owner = who.isManager ? 'staff/${who.uid}' : 'agents/${who.agentId}';
  return 'uploads/$owner/listings/$listingId/${at.millisecondsSinceEpoch}-$safe';
}

/// Demo: uploads are counted as if the pipeline took them at once.
class DemoListingMedia implements ListingMedia {
  final _photos = <String, List<String>>{};
  final _videos = <String, int>{};

  @override
  Future<ListingMediaState> state(StaffUser who, String listingId) async =>
      ListingMediaState(thumbs: [...?_photos[listingId]], videos: _videos[listingId] ?? 0);

  @override
  Future<void> upload(StaffUser who, String listingId, PickedFile file) async {
    final problem = uploadProblem(file);
    if (problem != null) throw ArgumentError(problem);
    if (videoTypes.contains(file.type)) {
      _videos[listingId] = (_videos[listingId] ?? 0) + 1;
    } else {
      (_photos[listingId] ??= []).add('media/listings/$listingId/${file.name}/thumb.webp');
    }
  }

  @override
  String? url(String path) => null;
}

/// Outside a browser there is no chooser; the web build overrides this.
class NoFilePicker implements FilePicker {
  @override
  Future<List<PickedFile>> pick({required String accept}) async => const [];
}

final listingMediaProvider = Provider<ListingMedia>((ref) => DemoListingMedia());
final filePickerProvider = Provider<FilePicker>((ref) => NoFilePicker());
