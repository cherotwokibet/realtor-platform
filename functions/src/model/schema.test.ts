import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collections, listing, lead } from './schema';
import { geohash, slugify } from './geo';
import { seedDocs } from '../seed/data';

test('geohash matches the reference implementation', () => {
  assert.equal(geohash(57.64911, 10.40744, 11), 'u4pruydqqvj'); // Wikipedia example
  assert.equal(geohash(-1.2921, 36.7856).length, 9);
  assert.throws(() => geohash(91, 0));
});

test('slugify', () => {
  assert.equal(slugify('2 bedroom apartment, Kilimani'), '2-bedroom-apartment-kilimani');
  assert.equal(slugify('  Café — Westlands!! '), 'cafe-westlands');
  assert.equal(slugify('1/8 acre plot, Syokimau'), '1-8-acre-plot-syokimau');
});

test('every seed document passes its collection schema', () => {
  const docs = seedDocs(new Date('2026-10-24T09:00:00Z'));
  assert.ok(docs.filter((d) => d.collection === 'listings').length >= 10);
  for (const d of docs) {
    const r = collections[d.collection].safeParse(d.data);
    assert.ok(r.success, `${d.collection}/${d.id}: ${r.success ? '' : r.error.message}`);
  }
});

test('seed listings point at real areas and agents, with unique slugs', () => {
  const docs = seedDocs();
  const ids = (c: string) => new Set(docs.filter((d) => d.collection === c).map((d) => d.id));
  const areas = ids('areas'), agents = ids('agents');
  const listings = docs.filter((d) => d.collection === 'listings').map((d) => d.data as any);
  for (const l of listings) {
    assert.ok(areas.has(l.area), l.area);
    assert.ok(agents.has(l.agentId), l.agentId);
  }
  assert.equal(new Set(listings.map((l) => l.slug)).size, listings.length);
});

test('at least 15 area guides, each with a guide and nearby places (P3 doneWhen)', () => {
  const areas = seedDocs().filter((d) => d.collection === 'areas').map((d) => d.data as any);
  assert.ok(areas.length >= 15, `${areas.length} areas`);
  for (const a of areas) {
    assert.ok(a.guide.length >= 60, `${a.name}: guide too short`);
    assert.ok(a.amenities.length >= 2, `${a.name}: needs nearby places`);
  }
});

test('schemas reject what Functions must refuse', () => {
  const ok = seedDocs().find((d) => d.collection === 'listings')!.data;
  assert.equal(listing.safeParse({ ...ok, priceKES: 65000.5 }).success, false, 'decimal shillings');
  assert.equal(listing.safeParse({ ...ok, depositMonths: undefined }).success, false, 'rent without deposit');
  assert.equal(listing.safeParse({ ...ok, slug: 'Not A Slug' }).success, false);
  const l = seedDocs().find((d) => d.collection === 'leads')!.data as any;
  assert.equal(lead.safeParse({ ...l, contact: {} }).success, false, 'lead without phone or email');
  assert.equal(lead.safeParse({ ...l, retainUntil: l.consentAt }).success, false, 'no retention date');
  assert.equal(lead.safeParse({ ...l, contact: { phone: '0712345678' } }).success, false, 'phone not E.164');
});
