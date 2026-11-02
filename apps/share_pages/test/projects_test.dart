import 'package:jaspr/server.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'listing_page_test.dart' show flat, tenant;

/// A made-up project (P5-s06).
final heights = ShareProject(
  slug: 'sample-heights',
  name: 'Sample Heights',
  developer: 'Sample Developers Ltd',
  area: 'kilimani',
  summary: 'Two towers near the mall.',
  completion: '2028-06',
  units: const [
    (type: 'studio', beds: 0, sizeSqm: 30, fromKES: 3500000, available: 0),
    (type: 'apartment', beds: 2, sizeSqm: 84, fromKES: 7200000, available: 40),
  ],
  paymentPlan: const [(stage: 'Deposit on booking', percent: 10), (stage: 'On handover', percent: 90)],
  fromKES: 3500000,
  updatedAt: DateTime.utc(2026, 11, 1),
);

final kilimani = const ShareArea(slug: 'kilimani', name: 'Kilimani', county: 'Nairobi', lat: -1.29, lng: 36.78);

Future<shelf.Response> get(String path, String tenantId) => Future.value(
      shareHandler(tenant(tenantId), InMemoryListingSource(const [flat], areas: [kilimani], projects: [heights]))(
        shelf.Request('GET', Uri.parse('https://x$path')),
      ),
    );

void main() {
  setUpAll(Jaspr.initializeApp);

  // demo-homes has offPlan on, realtime-estates has it off.
  test('/project/<slug> shows units, the payment plan and handover', () async {
    final res = await get('/project/${heights.slug}', 'demo-homes');
    expect(res.statusCode, 200);
    final html = await res.readAsString();
    expect(html, contains('<h1>Sample Heights</h1>'));
    expect(html, contains('June 2028'));
    expect(html, contains('2 bed apartment'));
    expect(html, contains('Studio'));
    expect(html, contains('Sold out'));
    expect(html, contains('Deposit on booking: 10%'));
    expect(html, contains('href="/area/kilimani"'));
    expect(html, contains('"@type":"ApartmentComplex"'));
  });

  test('/projects lists published projects', () async {
    final html = await (await get('/projects', 'demo-homes')).readAsString();
    expect(html, contains('href="/project/${heights.slug}"'));
    expect(html, contains('ready June 2028'));
  });

  test('with offPlan off, project pages are 404s and stay out of the sitemap and home page', () async {
    expect((await get('/projects', 'realtime-estates')).statusCode, 404);
    expect((await get('/project/${heights.slug}', 'realtime-estates')).statusCode, 404);
    expect(await (await get('/sitemap.xml', 'realtime-estates')).readAsString(), isNot(contains('/project/')));
    expect(await (await get('/', 'realtime-estates')).readAsString(), isNot(contains('href="/projects"')));
    expect(await (await get('/sitemap.xml', 'demo-homes')).readAsString(), contains('/project/${heights.slug}'));
    expect(await (await get('/', 'demo-homes')).readAsString(), contains('href="/projects"'));
  });

  test('an unknown or malformed slug is a 404', () async {
    expect((await get('/project/nope', 'demo-homes')).statusCode, 404);
    expect((await get('/project/Bad_Slug', 'demo-homes')).statusCode, 404);
  });

  test('labels', () {
    expect(completionLabel('2027-01'), 'January 2027');
    expect(completionLabel('soon'), 'soon');
    expect(unitLabel((type: 'villa', beds: 4, sizeSqm: null, fromKES: 1, available: 1)), '4 bed villa');
    expect(unitLabel((type: 'plot', beds: 0, sizeSqm: null, fromKES: 1, available: 1)), 'Plot');
  });

  test('projectFromDocument reads the REST shape', () {
    final p = projectFromDocument({
      'name': 'projects/p/databases/(default)/documents/projects/sample-heights',
      'fields': {
        'name': {'stringValue': 'Sample Heights'},
        'developer': {'stringValue': 'Sample Developers Ltd'},
        'area': {'stringValue': 'kilimani'},
        'summary': {'stringValue': 'x'},
        'completion': {'stringValue': '2028-06'},
        'fromKES': {'integerValue': '7200000'},
        'published': {'booleanValue': true},
        'units': {
          'arrayValue': {
            'values': [
              {
                'mapValue': {
                  'fields': {
                    'type': {'stringValue': 'apartment'},
                    'beds': {'integerValue': '2'},
                    'fromKES': {'integerValue': '7200000'},
                    'available': {'integerValue': '40'},
                  }
                }
              }
            ]
          }
        },
        'paymentPlan': {
          'arrayValue': {
            'values': [
              {'mapValue': {'fields': {'stage': {'stringValue': 'All'}, 'percent': {'integerValue': '100'}}}}
            ]
          }
        },
        'updatedAt': {'timestampValue': '2026-11-01T08:00:00Z'},
      },
    });
    expect(p.slug, 'sample-heights');
    expect(p.units.single, (type: 'apartment', beds: 2, sizeSqm: null, fromKES: 7200000, available: 40));
    expect(p.paymentPlan.single.percent, 100);
    expect(p.updatedAt, DateTime.utc(2026, 11, 1, 8));
  });
}
