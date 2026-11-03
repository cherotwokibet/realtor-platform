/**
 * Demo seed for the Firestore emulator and the sales demo tenant: Nairobi
 * areas, three fictional agents and a spread of listings. Market data only;
 * no realtor's own values. Phone numbers are in a fictional +254700000xxx range.
 */
import { geohash, slugify } from '../model/geo';
import type { CollectionName } from '../model/schema';

const DAY = 24 * 60 * 60 * 1000;

type Area = { slug: string; name: string; county: string; lat: number; lng: number; medianRent: number | null; guide: string; amenities: string[] };

/**
 * Sixteen areas across Nairobi and its commuter towns (P3 area guides).
 * Rents are indicative market figures for the demo, not a realtor's data;
 * each realtor rewrites guides and amenities in admin.
 */
export const AREAS: Area[] = [
  { slug: 'kilimani', name: 'Kilimani', county: 'Nairobi', lat: -1.2921, lng: 36.7856, medianRent: 75000,
    guide: 'Central and leafy, with apartment blocks close to the CBD and Upper Hill. Popular with young professionals; traffic on Argwings Kodhek and Ngong Road builds at peak hours.',
    amenities: ['Yaya Centre', 'Prestige Plaza', 'Nairobi Hospital nearby', 'Matatus on Ngong Road'] },
  { slug: 'westlands', name: 'Westlands', county: 'Nairobi', lat: -1.2676, lng: 36.8108, medianRent: 95000,
    guide: 'Office towers, malls and nightlife a short drive from the CBD. Serviced and short-stay apartments are common, and most buildings have backup power.',
    amenities: ['Sarit Centre', 'The Mall Westlands', 'Aga Khan Hospital nearby', 'Waiyaki Way expressway access'] },
  { slug: 'kileleshwa', name: 'Kileleshwa', county: 'Nairobi', lat: -1.2805, lng: 36.784, medianRent: 80000,
    guide: 'Quieter streets than Kilimani next door, with newer apartment blocks and some older family homes. Good access to Westlands and the CBD.',
    amenities: ['Kileleshwa shopping centre', 'Arboretum nearby', 'Othaya Road schools'] },
  { slug: 'lavington', name: 'Lavington', county: 'Nairobi', lat: -1.278, lng: 36.768, medianRent: 120000,
    guide: 'Large compounds, townhouses and gated estates on quiet roads. Popular with families for its schools and space.',
    amenities: ['Lavington Mall', 'Valley Arcade', 'International schools nearby'] },
  { slug: 'karen', name: 'Karen', county: 'Nairobi', lat: -1.3197, lng: 36.7073, medianRent: 150000,
    guide: 'Big plots, green space and standalone homes on the edge of the city. Most residents drive; expect borehole water and longer commutes to the CBD.',
    amenities: ['The Hub Karen', 'Karen Hospital', 'Nairobi National Park nearby'] },
  { slug: 'parklands', name: 'Parklands', county: 'Nairobi', lat: -1.2614, lng: 36.818, medianRent: 70000,
    guide: 'Established neighbourhood next to Westlands with family apartments, places of worship and good schools. Close to the CBD by matatu or car.',
    amenities: ['City Park', 'Aga Khan Hospital', 'Highridge shops'] },
  { slug: 'upper-hill', name: 'Upper Hill', county: 'Nairobi', lat: -1.2988, lng: 36.8143, medianRent: 90000,
    guide: 'Office district with a growing number of apartments, a walk or short ride from the CBD. Busy on weekdays, calm at weekends.',
    amenities: ['Nairobi Hospital', 'Kenyatta National Hospital nearby', 'Office towers'] },
  { slug: 'langata', name: "Lang'ata", county: 'Nairobi', lat: -1.35, lng: 36.757, medianRent: 60000,
    guide: 'Gated estates and maisonettes beside the national park, with easy access to the Southern Bypass.',
    amenities: ['Galleria Mall', 'Nairobi National Park', 'Southern Bypass access'] },
  { slug: 'south-b', name: 'South B', county: 'Nairobi', lat: -1.31, lng: 36.835, medianRent: 35000,
    guide: 'Busy middle-income estate between the CBD and the airport, with apartments, single rooms and plenty of matatus.',
    amenities: ['Capital Centre', 'Mombasa Road', 'Matatus to the CBD'] },
  { slug: 'embakasi', name: 'Embakasi', county: 'Nairobi', lat: -1.315, lng: 36.893, medianRent: 25000,
    guide: 'Large, affordable area close to JKIA and the industrial area. Expressway access shortens trips to the city.',
    amenities: ['JKIA nearby', 'Nairobi Expressway', 'Outer Ring Road'] },
  { slug: 'kasarani', name: 'Kasarani', county: 'Nairobi', lat: -1.221, lng: 36.897, medianRent: 22000,
    guide: 'Affordable bedsitters, hostels and apartments off Thika Road, popular with students and young families.',
    amenities: ['Kasarani stadium', 'Thika Road Mall nearby', 'Universities nearby'] },
  { slug: 'roysambu', name: 'Roysambu', county: 'Nairobi', lat: -1.218, lng: 36.884, medianRent: 20000,
    guide: 'Dense, lively estate along Thika Road with many new apartment blocks and quick matatu links to town.',
    amenities: ['Thika Road Mall', 'Garden City Mall', 'Matatus on Thika Road'] },
  { slug: 'ruaka', name: 'Ruaka', county: 'Kiambu', lat: -1.205, lng: 36.778, medianRent: 30000,
    guide: 'Fast-growing town just outside the city, with new apartments and good value for money. Limuru Road and the Northern Bypass connect to Westlands.',
    amenities: ['Two Rivers Mall nearby', 'Limuru Road', 'Northern Bypass'] },
  { slug: 'syokimau', name: 'Syokimau', county: 'Machakos', lat: -1.36, lng: 36.93, medianRent: 28000,
    guide: 'Gated estates and maisonettes off Mombasa Road, with a commuter train to the CBD.',
    amenities: ['Syokimau railway station', 'Gateway Mall', 'JKIA nearby'] },
  { slug: 'rongai', name: 'Rongai', county: 'Kajiado', lat: -1.396, lng: 36.76, medianRent: 18000,
    guide: 'Affordable town south of Karen and Langata, popular with students and families. Magadi Road traffic is heavy at peak hours.',
    amenities: ['Maasai Mall', 'Magadi Road', 'Universities nearby'] },
  { slug: 'kitengela', name: 'Kitengela', county: 'Kajiado', lat: -1.473, lng: 36.96, medianRent: 15000,
    guide: 'Growing town on Namanga Road with plots, bungalows and new estates at lower prices than the city.',
    amenities: ['Namanga Road', 'Kitengela town centre', 'JKIA within reach'] },
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

  for (const { slug, name, county, lat, lng, medianRent, guide, amenities } of AREAS) {
    docs.push({
      collection: 'areas',
      id: slug,
      data: {
        name,
        county,
        centre: { lat, lng, geohash: geohash(lat, lng) },
        guide,
        amenities,
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
    const area = AREAS.find((a) => a.slug === areaSlug)!;
    const lat = +(area.lat + dLat).toFixed(5);
    const lng = +(area.lng + dLng).toFixed(5);
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
  // One fictional off-plan project (P5-s06), shown only for tenants with offPlan on.
  docs.push({
    collection: 'projects',
    id: 'acacia-heights-ruaka',
    data: {
      name: 'Acacia Heights, Ruaka',
      developer: 'Sample Developers Ltd',
      area: 'ruaka',
      summary: 'Two towers of 1, 2 and 3 bedroom apartments ten minutes from Two Rivers, with a gym, a borehole and backup power. A sample project for demos.',
      completion: '2028-06',
      units: [
        { type: 'apartment', beds: 1, sizeSqm: 52, fromKES: 4_800_000, available: 24 },
        { type: 'apartment', beds: 2, sizeSqm: 84, fromKES: 7_200_000, available: 40 },
        { type: 'apartment', beds: 3, sizeSqm: 118, fromKES: 9_900_000, available: 12 },
      ],
      paymentPlan: [
        { stage: 'Deposit on booking', percent: 10 },
        { stage: 'On signing the sale agreement', percent: 20 },
        { stage: 'In 12 monthly instalments', percent: 50 },
        { stage: 'On handover', percent: 20 },
      ],
      fromKES: 4_800_000,
      published: true,
      updatedAt: now,
    },
  });

  return docs;
}
