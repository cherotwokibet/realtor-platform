import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:realtor_core/realtor_core.dart';

import '../listing_media.dart';

/// Uploads into the project's media bucket (`<project>-media`, made by
/// Terraform) and reads what the pipeline added from the listing document.
class StorageListingMedia implements ListingMedia {
  StorageListingMedia(this._storage, this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final FirebaseStorage _storage;
  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  @override
  Future<ListingMediaState> state(StaffUser who, String listingId) async {
    final d = (await _db.collection('listings').doc(listingId).get()).data() ?? const {};
    final media = [for (final m in (d['media'] as List<Object?>?) ?? const []) if (m is Map) m];
    return ListingMediaState(
      thumbs: [
        for (final m in media)
          if (m['kind'] != 'video')
            if (m['variants'] case {'thumb': final String thumb}) thumb,
      ],
      videos: media.where((m) => m['kind'] == 'video').length,
      lastError: (d['lastMediaError'] as Map?)?['reason'] as String?,
    );
  }

  @override
  Future<void> upload(StaffUser who, String listingId, PickedFile file) async {
    final problem = uploadProblem(file);
    if (problem != null) throw ArgumentError(problem);
    await _storage.ref(uploadPath(who, listingId, file.name, _clock())).putData(file.bytes, SettableMetadata(contentType: file.type));
  }

  @override
  Future<void> uploadAgentPhoto(StaffUser who, String agentId, PickedFile file) async {
    if (!photoTypes.contains(file.type) || file.bytes.length >= maxPhotoBytes) throw ArgumentError('${file.name}: a photo under 20 MB');
    await _storage.ref(agentPhotoPath(who, agentId, file.name, _clock())).putData(file.bytes, SettableMetadata(contentType: file.type));
  }

  @override
  String? url(String path) =>
      'https://firebasestorage.googleapis.com/v0/b/${_storage.bucket}/o/${Uri.encodeComponent(path)}?alt=media';
}
