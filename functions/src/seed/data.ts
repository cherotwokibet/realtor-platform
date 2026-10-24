/**
 * Demo seed for the Firestore emulator and the sales demo tenant: Nairobi
 * areas, three fictional agents and a spread of listings. Market data only;
 * no realtor's own values. Phone numbers are in a fictional +254700000xxx range.
 */
import { geohash, slugify } from '../model/geo';
import type { CollectionName } from '../model/schema';

const DAY = 24 * 60 * 60 * 1000;

const AREAS: [slug: string, name: string, county: string, lat: number, lng: number, medianRent: number | null][] = [
  ['kilimani', 'Kilimani', 'Nairobi', -1.2921, 36.7856, 75000],
  ['westlands', 'Westlands', 'Nairobi', -1.2676, 36.8108, 95000],
  ['kileleshwa', 'Kileleshwa', 'Nairobi', -1.2805, 36.784, 80000],
  ['lavington', 'Lavington', 'Nairobi', -1.278, 36.768, 120000],
  ['south-b', 'South B', 'Nairobi', -1.31, 36.835, 35000],
  ['kasarani', 'Kasarani', 'Nairobi', -1.221, 36.897, 22000],
  ['ruaka', 'Ruaka', 'Kiambu', -1.205, 36.778, 30000],
  ['syokimau', 'Syokimau', 'Machakos', -1.36, 36.93, 28000],
];

const AGENTS = [
  { id: 'agent-wanjiku', name: 'Wanjiku Mwangi', phone: '+254700000101', languages: ['en', 'sw'] },
  { id: 'agent-otieno', name: 'Brian Otieno', phone: '+254700000102', languages: ['en', 'sw'] },
  { id: 'agent-achieng', name: 'Achieng Odhiambo', phone: '+254700000103', languages: ['en'] },
] as const;

type L = [title: string, purpose: 'rent' | 'sale' | 'short-stay', type: string, beds: number, baths: number, price: number, area: string, estate: string | undefined, dLat: number, dLng: number];
const LISTINGS: L[] = [
  ['2 bedroom apartment, Kilimani', 'rent', 'apartment', 2, 2, 65000, 'kilimani', 'Argwings Kodhek', 0.002, -0.001],
  ['Bedsitter near Kasarani stadium', 'rent', 'bedsitter', 0, 1, 9500, 'kasarani', 'Mwiki', -0.003, 0.002],
  ['Single room, South B', 'rent', 'single-room', 0, 1, 7000, 'south-b', 'Plainsview', 0.001, 0.001],
  ['Studio with Wi-Fi, Westlands', 'short-stay', 'studio', 0, 1, 4500, 'westlands', 'Rhapta Road', 0.001, -0.002],
  ['3 bedroom maisonette, Syokimau', 'sale', 'maisonette', 3, 3, 12500000, 'syokimau', 'Katani Road', 0.004, 0.003],
  ['1 bedroom apartment, Ruaka', 'rent', 'apartment', 1, 1, 25000, 'ruaka', 'Ruaka Town', -0.001, 0.001],
  ['4 bedroom townhouse, Lavington', 'sale', 'townhouse', 4, 4, 38000000, 'lavington', 'James Gichuru', 0.002, 0.002],
  ['3 bedroom apartment, Kileleshwa', 'rent', 'apartment', 3, 3, 110000, 'kileleshwa', 'Othaya Road', -0.002, 0.001],
  ['Student hostel bed, Kasarani', 'rent', 'hostel', 1, 1, 6000, 'kasarani', 'Roysambu', 0.003, -0.003],
  ['2 bedroom apartment, Westlands', 'sale', 'apartment', 2, 2, 14500000, 'westlands', 'Brookside', -0.002, 0.003],
  ['5 bedroom villa, Lavington', 'rent', 'villa', 5, 5, 450000, 'lavington', 'Hatheru Road', -0.003, -0.002],
  ['1/8 acre plot, Syokimau', 'sale', 'land', 0, 0, 3200000, 'syokimau', undefined, -0.004, -0.001],
];

export type SeedDoc = { collection: CollectionName; id: string; data: Record<string, unknown> };

export function seedDocs(now = new Date()): SeedDoc[] {
  const docs: SeedDoc[] = [];
  const at = (days: number) => new Date(now.getTime() + days * DAY);

  for (const [slug, name, county, lat, lng, medianRent] of AREAS) {
    docs.push({
      collection: 'areas',
      id: slug,
      data: {
        name,
        county,
        centre: { lat, lng, geohash: geohash(lat, lng) },
        guide: `${name} guide: written by the realtor in admin (P3 area guides).`,
        amenities: [],
        stats: { medianRentKES: medianRent, listings: LISTINGS.filter((l) => l[6] === slug).length },
      },
    });
  }

  for (const a of AGENTS) {
    docs.push({
      collection: 'agents',
      id: a.id,
      data: { name: a.name, earbNo: 'TBC', phone: a.phone, whatsapp: a.phone, languages: [...a.languages], rating: null, responseMins: null, active: true },
    });
  }

  LISTINGS.forEach(([title, purpose, type, beds, baths, price, areaSlug, estate, dLat, dLng], i) => {
    const area = AREAS.find((a) => a[0] === areaSlug)!;
    const lat = +(area[3] + dLat).toFixed(5);
    const lng = +(area[4] + dLng).toFixed(5);
    const verified = i % 3 !== 2; // most live listings verified, some not
    docs.push({
      collection: 'listings',
      id: `listing-${String(i + 1).padStart(3, '0')}`,
      data: {
        title,
        slug: slugify(title),
        purpose,
        type,
        beds,
        baths,
        priceKES: price,
        ...(purpose === 'rent' ? { depositMonths: type === 'hostel' ? 1 : 2 } : {}),
        geo: { lat, lng, geohash: geohash(lat, lng) },
        area: areaSlug,
        ...(estate ? { estate } : {}),
        amenities: type === 'land' ? [] : ['parking', 'borehole', 'security'],
        utilities: purpose === 'sale' ? {} : { water: true, electricity: false, wifi: purpose === 'short-stay' },
        media: [],
        agentId: AGENTS[i % AGENTS.length].id,
        status: 'live',
        verifiedAt: verified ? at(-5) : null,
        expiresAt: verified ? at(25) : null,
        featuredUntil: i === 0 ? at(7) : null,
        stats: { views: 0, leads: 0 },
        createdAt: at(-10),
        updatedAt: at(-5),
      },
    });
  });

  docs.push({
    collection: 'leads',
    id: 'lead-001',
    data: {
      listingId: 'listing-001',
      agentId: AGENTS[0].id,
      channel: 'whatsapp',
      contact: { name: 'Demo Client', phone: '+254700000201' },
      message: 'Is the 2 bedroom in Kilimani still available?',
      stage: 'new',
      consentAt: at(-1),
      retainUntil: at(365),
      createdAt: at(-1),
    },
  });
  return docs;
}
