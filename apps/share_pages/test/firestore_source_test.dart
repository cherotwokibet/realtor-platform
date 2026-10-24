import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:test/test.dart';

/// A listing as the Firestore REST API returns it.
Map<String, Object?> restDoc({String? expiresAt = '2026-11-18T09:00:00Z'}) => {
      'name': 'projects/p/databases/(default)/documents/listings/listing-001',
      'fields': {
        'title': {'stringValue': '2 bedroom apartment, Kilimani'},
        'slug': {'stringValue': '2-bedroom-apartment-kilimani'},
        'purpose': {'stringValue': 'rent'},
        'type': {'stringValue': 'apartment'},
        'beds': {'integerValue': '2'},
        'baths': {'integerValue': '2'},
        'priceKES': {'integerValue': '65000'},
        'depositMonths': {'integerValue': '2'},
        'area': {'stringValue': 'kilimani'},
        'geo': {
          'mapValue': {
            'fields': {'lat': {'doubleValue': -1.2901}, 'lng': {'doubleValue': 36.7846}, 'geohash': {'stringValue': 'kzf0xxxxx'}}
          }
        },
        'amenities': {'arrayValue': {'values': [{'stringValue': 'parking'}]}},
        'media': {
          'arrayValue': {
            'values': [
              {
                'mapValue': {
                  'fields': {
                    'kind': {'stringValue': 'photo'},
                    'variants': {
                      'mapValue': {
                        'fields': {
                          'thumb': {'stringValue': 'media/x/thumb.webp'},
                          'card': {'stringValue': 'media/x/card.webp'},
                          'full': {'stringValue': 'media/x/full.webp'},
                        }
                      }
                    },
                  }
                }
              },
              {
                'mapValue': {'fields': {'kind': {'stringValue': 'video'}, 'variants': {'mapValue': {}}}}
              },
            ]
          }
        },
        'status': {'stringValue': 'live'},
        'verifiedAt': {'timestampValue': '2026-10-19T09:00:00Z'},
        'expiresAt': expiresAt == null ? {'nullValue': null} : {'timestampValue': expiresAt},
        'featuredUntil': {'nullValue': null},
        'updatedAt': {'timestampValue': '2026-10-19T09:00:00.123456Z'},
      },
    };

void main() {
  final now = DateTime.utc(2026, 10, 24, 9);

  test('decodes a Firestore REST document', () {
    final l = listingFromDocument(restDoc(), now);
    expect(l.id, 'listing-001');
    expect(l.purpose, Purpose.rent);
    expect(l.priceKES, 65000);
    expect(l.beds, 2);
    expect(l.lat, -1.2901);
    expect(l.amenities, ['parking']);
    expect(l.photos, [(card: 'media/x/card.webp', full: 'media/x/full.webp')], reason: 'videos are not photos');
    expect(l.verified, isTrue);
    expect(l.estate, isNull);
    expect(l.updatedAt, DateTime.utc(2026, 10, 19, 9, 0, 0, 123, 456));
  });

  test('verification lapses after expiresAt, or without one', () {
    expect(listingFromDocument(restDoc(expiresAt: '2026-10-24T08:59:59Z'), now).verified, isFalse);
    expect(listingFromDocument(restDoc(expiresAt: null), now).verified, isFalse);
  });
}
