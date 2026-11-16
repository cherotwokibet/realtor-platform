import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seedDocs } from '../seed/data';
import { collectionName, listingsSchema, toSearchDoc, toSearchParams } from './schema';
import { searchRelevantChange } from './sync';

const now = new Date('2026-10-24T09:00:00Z');
const seedListing = (id: string) => seedDocs(now).find((d) => d.id === id)!.data as Record<string, any>;

test('one collection per tenant', () => {
  assert.equal(collectionName('acme-realty'), 'acme-realty_listings');
  assert.equal(listingsSchema('acme-realty').name, 'acme-realty_listings');
});

test('live listings map to search docs; anything else is removed from search', () => {
  const l = seedListing('listing-001');
  const d = toSearchDoc('listing-001', l, now)!;
  assert.equal(d.priceKES, 65000);
  assert.deepEqual(d.location, [l.geo.lat, l.geo.lng]);
  assert.equal(d.verified, true);
  assert.equal(d.featured, true);
  assert.equal(toSearchDoc('x', { ...l, status: 'pending' }, now), null);
  assert.equal(toSearchDoc('x', undefined, now), null);
});

test('the description is searchable, weighted below title, area and estate (P7-s02)', () => {
  const l = seedListing('listing-001');
  assert.equal(toSearchDoc('x', { ...l, description: 'Near Yaya Centre.' }, now)!.description, 'Near Yaya Centre.');
  assert.equal('description' in toSearchDoc('x', { ...l, description: undefined }, now)!, false);
  assert.ok(listingsSchema('t').fields!.some((f) => f.name === 'description' && f.optional));
  const p = toSearchParams({ purpose: 'rent', q: 'yaya' } as any);
  assert.equal(p.query_by, 'title,estate,area,amenities,description');
  assert.equal(String(p.query_by_weights).split(',').length, 5);
});

test('drawn polygon becomes a Typesense geo polygon filter; too few or too many corners are ignored (P3-s04)', () => {
  const tri = [{ lat: -1.28, lng: 36.8 }, { lat: -1.28, lng: 36.84 }, { lat: -1.3, lng: 36.82 }];
  assert.match(toSearchParams({ purpose: 'rent', polygon: tri } as any).filter_by!, /location:\(-1\.28, 36\.8, -1\.28, 36\.84, -1\.3, 36\.82\)$/);
  assert.doesNotMatch(toSearchParams({ purpose: 'rent', polygon: tri.slice(0, 2) } as any).filter_by!, /location/);
  const many = Array.from({ length: 21 }, (_, i) => ({ lat: -1.2 - i / 1000, lng: 36.8 + (i % 2) / 100 }));
  assert.doesNotMatch(toSearchParams({ purpose: 'rent', polygon: many } as any).filter_by!, /location/);
});

test('verification lapses after expiresAt', () => {
  const l = seedListing('listing-001');
  assert.equal(toSearchDoc('x', { ...l, expiresAt: new Date(now.getTime() - 1) }, now)!.verified, false);
  assert.equal(toSearchDoc('x', { ...seedListing('listing-003') }, now)!.verified, false, 'never verified');
});

test('URL filters become a Typesense query', () => {
  const p = toSearchParams({ purpose: 'rent', types: ['apartment'], areas: ['kilimani'], minBeds: 2, maxPriceKES: 60000, sort: 'price-asc' });
  assert.equal(p.filter_by, 'purpose:=[`rent`] && type:=[`apartment`] && area:=[`kilimani`] && beds:>=2 && priceKES:[0..60000]');
  assert.equal(p.sort_by, 'priceKES:asc');
  assert.equal(p.q, '*');
});

test('geo radius, sorting by distance and safe paging', () => {
  const p = toSearchParams({ purpose: 'sale', near: { lat: -1.29, lng: 36.82, km: 5 }, sort: 'nearest', perPage: 500, page: 0 });
  assert.match(p.filter_by!, /location:\(-1\.29, 36\.82, 5 km\)/);
  assert.equal(p.sort_by, 'location(-1.29, 36.82):asc');
  assert.equal(p.per_page, 50);
  assert.equal(p.page, 1);
});

test('backticks in user input cannot break out of a filter value', () => {
  const p = toSearchParams({ purpose: 'rent', areas: ['kilimani` || purpose:=`sale'] });
  assert.equal(p.filter_by, 'purpose:=[`rent`] && area:=[`kilimani || purpose:=sale`]');
});

test('counter-only writes (views, leads, taps) do not re-sync search', () => {
  const l = seedListing('listing-001');
  assert.equal(searchRelevantChange(l, { ...l, stats: { ...l.stats, whatsapps: 3 } }), false);
  assert.equal(searchRelevantChange(l, { ...l, priceKES: 70000 }), true);
  assert.equal(searchRelevantChange(l, { ...l, geo: { ...l.geo, lat: -1.3 } }), true);
  assert.equal(searchRelevantChange(l, Object.fromEntries(Object.entries(l).reverse())), false, 'key order');
  assert.equal(searchRelevantChange(undefined, l), true, 'created');
  assert.equal(searchRelevantChange(l, undefined), true, 'deleted');
});

test('More Filters: furnishing, floor plans, tours and verified-first reach the query; cards get their photos', () => {
  const by = String(toSearchParams({ purpose: 'rent', furnished: false, floorPlan: true, video: true, tour: true, verifiedFirst: true }).filter_by);
  assert.match(by, /amenities:!=\[`furnished`\]/);
  assert.match(by, /hasFloorPlan:=true/);
  assert.match(by, /hasVideo:=true/);
  assert.match(by, /has360:=true/);
  assert.match(String(toSearchParams({ purpose: 'rent', furnished: true }).filter_by), /amenities:=\[`furnished`\]/);
  assert.match(String(toSearchParams({ purpose: 'rent', verifiedFirst: true, sort: 'price-asc' }).sort_by), /^verified:desc,priceKES:asc$/);

  const photo = (n: number) => ({ kind: 'photo', variants: { thumb: `t${n}`, card: `c${n}` }, blurhash: 'b' });
  const doc = toSearchDoc('l1', {
    status: 'live', title: 'T', slug: 't', purpose: 'rent', type: 'apartment', beds: 1, baths: 1, priceKES: 1, area: 'a', geo: { lat: 0, lng: 0 },
    media: [...[1, 2, 3, 4, 5, 6, 7].map(photo), { kind: 'floor-plan', variants: { full: 'f' } }],
  })!;
  assert.deepEqual(doc.photos, ['c1', 'c2', 'c3', 'c4', 'c5', 'c6']);
  assert.equal(doc.hasFloorPlan, true);
  assert.equal(doc.hasVideo, false);
  assert.equal(doc.has360, false);
});

test('Beds & Baths: exact counts, the top choice meaning that many or more; Newest sorts strictly by date', () => {
  assert.match(String(toSearchParams({ purpose: 'rent', beds: [2, 1] }).filter_by), /beds:=\[1,2\]/);
  assert.match(String(toSearchParams({ purpose: 'rent', beds: [1, 8] }).filter_by), /\(beds:=\[1\] \|\| beds:>=8\)/);
  assert.match(String(toSearchParams({ purpose: 'rent', baths: [6] }).filter_by), /baths:>=6/);
  assert.doesNotMatch(String(toSearchParams({ purpose: 'rent', beds: [0, 99] }).filter_by), /beds/);
  assert.equal(toSearchParams({ purpose: 'rent', sort: 'latest' }).sort_by, 'updatedAt:desc');
});
