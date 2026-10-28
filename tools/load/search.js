// k6 load test for listing search (D4): the Typesense queries the app sends
// for its filters. Read-only.
//
//   TYPESENSE_URL=https://<host> TYPESENSE_SEARCH_KEY=<search-only key> \
//   COLLECTION=<tenantId>_listings PROFILE=load k6 run tools/load/search.js
//
// Use a search-only (scoped) key from the environment, never an admin key, and
// never write one into this repo. PROFILE: smoke or load (up to 30 users, ~9 min).
import http from 'k6/http';
import { check, sleep } from 'k6';

const HOST = (__ENV.TYPESENSE_URL || '').replace(/\/$/, '');
const KEY = __ENV.TYPESENSE_SEARCH_KEY || '';
const COLLECTION = __ENV.COLLECTION || '';
const PROFILE = __ENV.PROFILE || 'smoke';

const profiles = {
  smoke: { vus: 1, duration: '30s' },
  load: {
    stages: [
      { duration: '2m', target: 30 },
      { duration: '5m', target: 30 },
      { duration: '2m', target: 0 },
    ],
  },
};

export const options = {
  ...profiles[PROFILE],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<300'],
    checks: ['rate>0.99'],
  },
};

export function setup() {
  if (!HOST || !KEY || !COLLECTION) throw new Error('Set TYPESENSE_URL, TYPESENSE_SEARCH_KEY and COLLECTION.');
  // The areas actually indexed, so filters match real listings.
  const res = http.get(`${HOST}/collections/${COLLECTION}/documents/search?q=*&facet_by=area&per_page=0`, {
    headers: { 'X-TYPESENSE-API-KEY': KEY },
  });
  if (res.status !== 200) throw new Error(`facet query answered ${res.status}`);
  const counts = (res.json('facet_counts') || [])[0];
  return { areas: counts ? counts.counts.map((c) => c.value) : [] };
}

const pick = (list) => list[Math.floor(Math.random() * list.length)];

// Shapes the app sends: purpose always, often an area, sometimes beds and a
// price cap; sorted by featured then newest, 20 per page.
function query(areas) {
  const filters = [`purpose:=${pick(['rent', 'rent', 'rent', 'sale'])}`];
  if (areas.length && Math.random() < 0.7) filters.push(`area:=${pick(areas)}`);
  if (Math.random() < 0.4) filters.push(`beds:>=${pick([1, 2, 3])}`);
  if (Math.random() < 0.3) filters.push(`priceKES:<=${pick([40000, 80000, 150000])}`);
  const params = {
    q: Math.random() < 0.2 ? pick(['furnished', 'apartment', 'garden', 'parking']) : '*',
    query_by: 'title,estate,area,amenities',
    filter_by: filters.join(' && '),
    sort_by: 'featured:desc,updatedAt:desc',
    per_page: '20',
  };
  return Object.entries(params).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
}

export default function (data) {
  const res = http.get(`${HOST}/collections/${COLLECTION}/documents/search?${query(data.areas)}`, {
    headers: { 'X-TYPESENSE-API-KEY': KEY },
    tags: { name: 'search' },
  });
  check(res, {
    'status 200': (r) => r.status === 200,
    'has hits': (r) => Array.isArray(r.json('hits')),
  });
  sleep(1 + Math.random() * 2);
}
