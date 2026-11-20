/// The features and amenities a listing can have, as the admin offers them
/// and the site's filters and listing page show them. Stored by key; a
/// listing may also carry its own words for anything not here.
library;

/// (key, label, group), grouped and in the order the admin lists them.
const listingAmenities = <(String, String, String)>[
  ('furnished', 'Furnished', 'Features'),
  ('balcony', 'Balcony', 'Features'),
  ('air-conditioning', 'Air conditioning', 'Features'),
  ('servant-quarters', 'Servant quarters (DSQ)', 'Features'),
  ('pet-friendly', 'Pet friendly', 'Features'),
  ('parking', 'Parking', 'Building'),
  ('lift', 'Lift', 'Building'),
  ('shops', 'Shops nearby', 'Building'),
  ('security', 'Security', 'Security'),
  ('cctv', 'CCTV', 'Security'),
  ('gym', 'Gym', 'Health and fitness'),
  ('swimming-pool', 'Swimming pool', 'Health and fitness'),
  ('borehole', 'Borehole', 'Utilities'),
  ('water', 'Reliable water', 'Utilities'),
  ('wifi', 'Wi-Fi', 'Utilities'),
  ('backup-generator', 'Backup generator', 'Utilities'),
  ('solar-water-heating', 'Solar water heating', 'Utilities'),
  ('garden', 'Garden', 'Outdoors'),
  ('playground', 'Playground', 'Outdoors'),
];

/// The label for an amenity key, or the stored words as they are.
String amenityLabel(String key) => listingAmenities.where((a) => a.$1 == key).map((a) => a.$2).firstOrNull ?? key;
