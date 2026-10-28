// k6 load test for the share pages (D2): the pages Google, WhatsApp and
// visitors hit. GET only; it never posts the enquiry or viewing forms, so
// it creates no leads.
//
//   BASE_URL=https://<project>-share.web.app PROFILE=load k6 run tools/load/share-pages.js
//
// PROFILE: smoke (1 user, 30 s; CI runs this) or load (up to 50 users, ~9 min).
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = (__ENV.BASE_URL || '').replace(/\/$/, '');
const PROFILE = __ENV.PROFILE || 'smoke';

const profiles = {
  smoke: { vus: 1, duration: '30s' },
  load: {
    stages: [
      { duration: '2m', target: 50 },
      { duration: '5m', target: 50 },
      { duration: '2m', target: 0 },
    ],
  },
};

export const options = {
  ...profiles[PROFILE],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{kind:page}': [PROFILE === 'smoke' ? 'p(95)<1500' : 'p(95)<800'],
    checks: ['rate>0.99'],
  },
};

// Paths come from the live sitemap, so the test follows whatever the tenant
// has published. Its <loc>s carry the share domain; only the path is kept.
export function setup() {
  if (!BASE) throw new Error('Set BASE_URL to the share pages origin.');
  const res = http.get(`${BASE}/sitemap.xml`);
  if (res.status !== 200) throw new Error(`sitemap.xml answered ${res.status}`);
  const paths = [...res.body.matchAll(/<loc>([^<]+)<\/loc>/g)]
    .map((m) => m[1].replace(/&amp;/g, '&').replace(/^https?:\/\/[^/]+/, '') || '/')
    .slice(0, 500);
  return {
    home: paths.filter((p) => p === '/'),
    listings: paths.filter((p) => p.startsWith('/listing/')),
    areas: paths.filter((p) => p.startsWith('/area/')),
    agents: paths.filter((p) => p.startsWith('/agent/')),
  };
}

const pick = (list) => list[Math.floor(Math.random() * list.length)];

function page(path) {
  const res = http.get(`${BASE}${path}`, { tags: { kind: 'page', name: path.split('/')[1] || 'home' } });
  check(res, {
    'status 200': (r) => r.status === 200,
    'is html': (r) => (r.headers['Content-Type'] || '').startsWith('text/html'),
  });
}

// Roughly how visitors arrive: mostly a shared listing link, then its area
// or agent, now and then the home page.
export default function (paths) {
  const roll = Math.random();
  if (roll < 0.6 && paths.listings.length) page(pick(paths.listings));
  else if (roll < 0.8 && paths.areas.length) page(pick(paths.areas));
  else if (roll < 0.9 && paths.agents.length) page(pick(paths.agents));
  else page('/');
  sleep(1 + Math.random() * 2);
}
