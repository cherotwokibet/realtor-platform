/// An agent's public profile (P5-s04), as managers edit it in the admin and
/// the `saveAgent` Function stores it. [problems] mirrors the Function.
library;

import 'phone.dart';

const agentLanguages = {'en': 'English', 'sw': 'Kiswahili'};

class AgentProfile {
  const AgentProfile({
    this.id,
    this.name = '',
    this.earbNo = '',
    this.phone = '',
    this.whatsapp = '',
    this.languages = const ['en'],
    this.active = true,
    this.photo,
    this.rating,
    this.responseMins,
  });

  /// Null for a new agent; the Function makes one from the name.
  final String? id;
  final String name, earbNo, phone, whatsapp;
  final List<String> languages;
  final bool active;

  /// Set by the media pipeline and nightly jobs; shown, never sent.
  final String? photo;
  final double? rating;
  final int? responseMins;

  factory AgentProfile.fromDoc(String id, Map<String, Object?> d) => AgentProfile(
        id: id,
        name: d['name'] as String? ?? '',
        earbNo: d['earbNo'] as String? ?? '',
        phone: d['phone'] as String? ?? '',
        whatsapp: d['whatsapp'] as String? ?? '',
        languages: [for (final l in (d['languages'] as List<Object?>?) ?? const ['en']) '$l'],
        active: d['active'] as bool? ?? false,
        photo: d['photo'] as String?,
        rating: (d['rating'] as num?)?.toDouble(),
        responseMins: (d['responseMins'] as num?)?.toInt(),
      );

  /// What is wrong, by field. Phones may be typed as 0712 345 678.
  Map<String, String> problems() => {
        if (name.trim().length < 2 || name.trim().length > 80) 'name': 'Use 2 to 80 characters.',
        if (earbNo.trim().isEmpty || earbNo.trim().length > 40) 'earbNo': 'Enter the EARB registration number.',
        if (normaliseKenyanPhone(phone) == null) 'phone': 'A Kenyan mobile, like 0712 345 678.',
        if (normaliseKenyanPhone(whatsapp) == null) 'whatsapp': 'A Kenyan mobile, like 0712 345 678.',
        if (languages.isEmpty || languages.any((l) => !agentLanguages.containsKey(l))) 'languages': 'Pick at least one.',
      };

  /// The `saveAgent` input, phones as E.164.
  Map<String, Object?> toCallable() => {
        if (id != null) 'agentId': id,
        'name': name.trim(),
        'earbNo': earbNo.trim(),
        'phone': normaliseKenyanPhone(phone) ?? phone,
        'whatsapp': normaliseKenyanPhone(whatsapp) ?? whatsapp,
        'languages': languages,
        'active': active,
      };
}
