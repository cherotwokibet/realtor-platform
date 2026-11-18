import { test } from 'node:test';
import assert from 'node:assert/strict';
import { indexRow } from './listing-index';

test('an index row keeps the card fields, times as milliseconds, and drops the rest', () => {
  const ts = (ms: number) => ({ toMillis: () => ms });
  const row = indexRow('l1', {
    slug: 'flat-1', title: 'Flat', purpose: 'rent', type: 'apartment', beds: 2, baths: 1, priceKES: 50000, area: 'kilimani',
    agentId: 'a1', geo: { lat: -1.29, lng: 36.78, geohash: 'kzf0' }, verifiedAt: ts(1), expiresAt: ts(2), updatedAt: ts(3),
    status: 'live', description: 'long text', ownerPhone: '+254700000000', viewingFeeKES: 500,
    media: [
      { kind: 'photo', path: 'raw/x.jpg', blurhash: 'LKO2', variants: { card: 'c.webp', thumb: 't.webp', full: 'f.webp' } },
      { kind: 'video', variants: { hls: 'v.m3u8', poster: 'p.jpg' } },
    ],
  });
  assert.deepEqual(row, {
    id: 'l1', slug: 'flat-1', title: 'Flat', purpose: 'rent', type: 'apartment', beds: 2, baths: 1, priceKES: 50000, area: 'kilimani',
    agentId: 'a1', geo: { lat: -1.29, lng: 36.78, geohash: 'kzf0' }, verifiedAt: 1, expiresAt: 2, updatedAt: 3,
    media: [
      { kind: 'photo', blurhash: 'LKO2', variants: { card: 'c.webp', thumb: 't.webp' } },
      { kind: 'video', variants: { poster: 'p.jpg' } },
    ],
  });
});
