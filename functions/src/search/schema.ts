/**
 * Typesense search for listings (D4). Pure parts: the collection schema,
 * the Firestore listing -> search document mapping, and the filter -> query
 * translation the app and share pages use. Only live listings are indexed.
 */
import type { CollectionCreateSchema } from 'typesense/lib/Typesense/Collections';
import type { SearchParams } from 'typesense/lib/Typesense/Documents';

/** One collection per tenant on a shared Typesense server: `<tenantId>_listings`. */
export const collectionName = (tenantId: string) => `${tenantId}_listings`;

export function listingsSchema(tenantId: string): CollectionCreateSchema {
  return {
    name: collectionName(tenantId),
    fields: [
      { name: 'title', type: 'string' },
      { name: 'slug', type: 'string', index: false, optional: true },
      { name: 'purpose', type: 'string', facet: true },
      { name: 'type', type: 'string', facet: true },
      { name: 'beds', type: 'int32', facet: true },
      { name: 'baths', type: 'int32', facet: true },
      { name: 'priceKES', type: 'int64', facet: true },
      { name: 'area', type: 'string', facet: true },
      { name: 'estate', type: 'string', optional: true },
      { name: 'amenities', type: 'string[]', facet: true },
      { name: 'location', type: 'geopoint' },
      { name: 'verified', type: 'bool', facet: true },
      { name: 'featured', type: 'bool' },
      { name: 'thumb', type: 'string', index: false, optional: true },
      { name: 'blurhash', type: 'string', index: false, optional: true },
      { name: 'updatedAt', type: 'int64' },
    ],
    default_sorting_field: 'updatedAt',
  };
}

export interface SearchDoc {
  id: string;
  title: string;
  slug: string;
  purpose: string;
  type: string;
  beds: number;
  baths: number;
  priceKES: number;
  area: string;
  estate?: string;
  amenities: string[];
  location: [number, number];
  verified: boolean;
  featured: boolean;
  thumb?: string;
  blurhash?: string;
  updatedAt: number;
}

const millis = (v: unknown): number | null =>
  v == null ? null : v instanceof Date ? v.getTime() : typeof (v as { toMillis?: () => number }).toMillis === 'function' ? (v as { toMillis(): number }).toMillis() : null;

/** The search document for a listing, or null when it must not be searchable. */
export function toSearchDoc(id: string, l: Record<string, any> | undefined, now = new Date()): SearchDoc | null {
  if (!l || l.status !== 'live') return null;
  const expires = millis(l.expiresAt);
  const featuredUntil = millis(l.featuredUntil);
  const photo = (l.media ?? []).find((m: any) => m.kind === 'photo');
  return {
    id,
    title: l.title,
    slug: l.slug,
    purpose: l.purpose,
    type: l.type,
    beds: l.beds,
    baths: l.baths,
    priceKES: l.priceKES,
    area: l.area,
    ...(l.estate ? { estate: l.estate } : {}),
    amenities: l.amenities ?? [],
    location: [l.geo.lat, l.geo.lng],
    verified: millis(l.verifiedAt) !== null && expires !== null && expires > now.getTime(),
    featured: featuredUntil !== null && featuredUntil > now.getTime(),
    ...(photo ? { thumb: photo.variants.thumb, blurhash: photo.blurhash } : {}),
    updatedAt: millis(l.updatedAt) ?? now.getTime(),
  };
}

/** What a search screen or a share-page URL asks for (/rent/apartments/kilimani?beds=2&max=60000). */
export interface ListingFilters {
  q?: string;
  purpose: 'rent' | 'sale' | 'short-stay';
  types?: string[];
  areas?: string[];
  minBeds?: number;
  minPriceKES?: number;
  maxPriceKES?: number;
  amenities?: string[];
  verifiedOnly?: boolean;
  /** Radius search around a point, in km. */
  near?: { lat: number; lng: number; km: number };
  /** Draw-an-area search: 3 to 20 corners, implicitly closed. */
  polygon?: Array<{ lat: number; lng: number }>;
  sort?: 'newest' | 'price-asc' | 'price-desc' | 'nearest';
  page?: number;
  perPage?: number;
}

const list = (xs: string[]) => `[${xs.map((x) => '`' + x.replace(/`/g, '') + '`').join(',')}]`;

export function toSearchParams(f: ListingFilters): SearchParams<SearchDoc> {
  const by: string[] = [`purpose:=${list([f.purpose])}`];
  if (f.types?.length) by.push(`type:=${list(f.types)}`);
  if (f.areas?.length) by.push(`area:=${list(f.areas)}`);
  if (f.amenities?.length) for (const a of f.amenities) by.push(`amenities:=${list([a])}`);
  if (f.minBeds != null) by.push(`beds:>=${Math.trunc(f.minBeds)}`);
  if (f.minPriceKES != null || f.maxPriceKES != null)
    by.push(`priceKES:[${Math.trunc(f.minPriceKES ?? 0)}..${Math.trunc(f.maxPriceKES ?? 10_000_000_000)}]`);
  if (f.verifiedOnly) by.push('verified:=true');
  if (f.near) by.push(`location:(${f.near.lat}, ${f.near.lng}, ${f.near.km} km)`);

  if (f.polygon && f.polygon.length >= 3 && f.polygon.length <= 20)
    by.push(`location:(${f.polygon.map((p) => `${p.lat}, ${p.lng}`).join(', ')})`);

  const sort = {
    newest: 'featured:desc,updatedAt:desc',
    'price-asc': 'priceKES:asc',
    'price-desc': 'priceKES:desc',
    nearest: f.near ? `location(${f.near.lat}, ${f.near.lng}):asc` : 'updatedAt:desc',
  }[f.sort ?? 'newest'];

  return {
    q: f.q?.trim() || '*',
    query_by: 'title,estate,area,amenities',
    filter_by: by.join(' && '),
    facet_by: 'type,beds,area,amenities,verified,priceKES',
    facet_stats_fields: 'priceKES',
    sort_by: sort,
    num_typos: 2,
    page: Math.max(1, f.page ?? 1),
    per_page: Math.min(50, Math.max(1, f.perPage ?? 20)),
  } as SearchParams<SearchDoc>;
}
