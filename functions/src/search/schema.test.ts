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
