/**
 * Integration test against a real Typesense (CI service container):
 *   TYPESENSE_HOST=localhost TYPESENSE_API_KEY=ci-key npm --prefix functions run test:typesense
 */
import { before, test } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'typesense';
import { seedDocs } from '../seed/data';
import { collectionName, toSearchParams, type SearchDoc } from './schema';
import { ensureCollection, syncListing } from './sync';

const tenant = 'ci-tenant';
const now = new Date('2026-10-24T09:00:00Z');
let client: Client;

before(async () => {
  assert.ok(process.env.TYPESENSE_HOST && process.env.TYPESENSE_API_KEY, 'needs TYPESENSE_HOST and TYPESENSE_API_KEY');
  client = new Client({
    nodes: [{ host: process.env.TYPESENSE_HOST!, port: 8108, protocol: 'http' }],
    apiKey: process.env.TYPESENSE_API_KEY!,
    connectionTimeoutSeconds: 5,
  });
  await client.collections(collectionName(tenant)).delete().catch(() => undefined);
  await ensureCollection(client, tenant);
  await ensureCollection(client, tenant); // idempotent
  for (const d of seedDocs(now).filter((d) => d.collection === 'listings')) {
    await syncListing(client, tenant, d.id, d.data, now);
  }
});

const search = (f: Parameters<typeof toSearchParams>[0]) =>
  client.collections<SearchDoc>(collectionName(tenant)).documents().search(toSearchParams(f));

test('facets come back with counts', async () => {
  const r = await search({ purpose: 'rent' });
  assert.ok(r.found >= 5);
  const types = r.facet_counts!.find((f) => f.field_name === 'type')!;
  assert.ok(types.counts.some((c) => c.value === 'apartment' && c.count >= 2));
});

test('price range, beds and area filters', async () => {
  const r = await search({ purpose: 'rent', areas: ['kilimani', 'kileleshwa'], minBeds: 2, maxPriceKES: 100000 });
  assert.deepEqual(r.hits!.map((h) => h.document.id), ['listing-001']);
});

test('geo radius around Kasarani', async () => {
  const r = await search({ purpose: 'rent', near: { lat: -1.221, lng: 36.897, km: 2 }, sort: 'nearest' });
  assert.ok(r.found >= 2);
  assert.ok(r.hits!.every((h) => h.document.area === 'kasarani'));
});

test('typo tolerance: "apartmnt kilimni" still finds the Kilimani flat', async () => {
  const r = await search({ purpose: 'rent', q: 'apartmnt kilimni' });
  assert.equal(r.hits![0].document.id, 'listing-001');
});

test('answers in under 100 ms (doneWhen)', async () => {
  const r = await search({ purpose: 'rent', minBeds: 1, sort: 'price-asc' });
  assert.ok(r.search_time_ms < 100, `${r.search_time_ms} ms`);
});

test('a listing that leaves live drops out of search', async () => {
  const l = seedDocs(now).find((d) => d.id === 'listing-001')!.data;
  assert.equal(await syncListing(client, tenant, 'listing-001', { ...l, status: 'let' }, now), 'removed');
  assert.equal((await search({ purpose: 'rent', areas: ['kilimani'] })).found, 0);
  assert.equal(await syncListing(client, tenant, 'listing-001', undefined, now), 'removed', 'deleting twice is fine');
});
