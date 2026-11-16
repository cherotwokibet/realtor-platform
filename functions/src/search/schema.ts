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
      { name: 'description', type: 'string', optional: true },
      { name: 'amenities', type: 'string[]', facet: true },
      { name: 'location', type: 'geopoint' },
      { name: 'verified', type: 'bool', facet: true },
      { name: 'featured', type: 'bool' },
      { name: 'thumb', type: 'string', index: false, optional: true },
      { name: 'blurhash', type: 'string', index: false, optional: true },
      { name: 'photos', type: 'string[]', index: false, optional: true },
      { name: 'hasFloorPlan', type: 'bool', optional: true },
      { name: 'hasVideo', type: 'bool', optional: true },
      { name: 'has360', type: 'bool', optional: true },
      { name: 'videoPoster', type: 'string', index: false, optional: true },
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
  description?: string;
  amenities: string[];
  location: [number, number];
  verified: boolean;
  featured: boolean;
  thumb?: string;
  blurhash?: string;
  /** Card-size copies of the first few photos, for the card's carousel. */
  photos?: string[];
  hasFloorPlan: boolean;
  hasVideo: boolean;
  has360: boolean;
  /** A frame of the video, shown last in the card's carousel. */
  videoPoster?: string;
  updatedAt: number;
}

const millis = (v: unknown): number | null =>
  v == null ? null : v instanceof Date ? v.getTime() : typeof (v as { toMillis?: () => number }).toMillis === 'function' ? (v as { toMillis(): number }).toMillis() : null;

/** The search document for a listing, or null when it must not be searchable. */
export function toSearchDoc(id: string, l: Record<string, any> | undefined, now = new Date()): SearchDoc | null {
  if (!l || l.status !== 'live') return null;
  const expires = millis(l.expiresAt);
  const featuredUntil = millis(l.featuredUntil);
  const media: any[] = l.media ?? [];
  const photo = media.find((m: any) => m.kind === 'photo');
  const cards = media
    .filter((m: any) => m.kind === 'photo')
    .slice(0, 6)
    .map((m: any) => m.variants?.card ?? m.variants?.thumb)
    .filter((p: unknown) => typeof p === 'string');
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
    ...(l.description ? { description: l.description } : {}),
    amenities: l.amenities ?? [],
    location: [l.geo.lat, l.geo.lng],
    verified: millis(l.verifiedAt) !== null && expires !== null && expires > now.getTime(),
    featured: featuredUntil !== null && featuredUntil > now.getTime(),
    ...(photo ? { thumb: photo.variants.thumb, blurhash: photo.blurhash } : {}),
    ...(cards.length ? { photos: cards } : {}),
    hasFloorPlan: media.some((m: any) => m.kind === 'floor-plan'),
    hasVideo: media.some((m: any) => m.kind === 'video'),
    has360: media.some((m: any) => m.kind === 'tour-360'),
    ...(media.find((m: any) => m.kind === 'video')?.variants?.poster ? { videoPoster: media.find((m: any) => m.kind === 'video').variants.poster } : {}),
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
  /** Verified homes sort above the rest, whatever the sort. */
  verifiedFirst?: boolean;
  /** true: furnished only; false: unfurnished only. */
  furnished?: boolean;
  floorPlan?: boolean;
  /** Only homes with a video tour. */
  video?: boolean;
  /** Only homes with a 360° tour. */
  tour?: boolean;
  /** Exact bedroom counts, any of them; 8 means 8 or more. */
  beds?: number[];
  /** Exact bathroom counts, any of them; 6 means 6 or more. */
  baths?: number[];
  /** Radius search around a point, in km. */
  near?: { lat: number; lng: number; km: number };
  /** Draw-an-area search (P3-s04): 3 to 20 corners, implicitly closed. */
  polygon?: Array<{ lat: number; lng: number }>;
  sort?: 'newest' | 'latest' | 'price-asc' | 'price-desc' | 'nearest';
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
  if (f.furnished != null) by.push(`amenities:${f.furnished ? '=' : '!='}${list(['furnished'])}`);
  if (f.floorPlan) by.push('hasFloorPlan:=true');
  if (f.video) by.push('hasVideo:=true');
  if (f.tour) by.push('has360:=true');
  const counts = (field: string, xs: number[] | undefined, max: number) => {
    const ok = [...new Set((xs ?? []).map(Math.trunc).filter((n) => n >= 1 && n <= max))].sort((a, b) => a - b);
    if (!ok.length) return;
    const exact = ok.filter((n) => n < max);
    const parts = [...(exact.length ? [`${field}:=[${exact.join(',')}]`] : []), ...(ok.includes(max) ? [`${field}:>=${max}`] : [])];
    by.push(parts.length > 1 ? `(${parts.join(' || ')})` : parts[0]);
  };
  counts('beds', f.beds, 8);
  counts('baths', f.baths, 6);
  if (f.near) by.push(`location:(${f.near.lat}, ${f.near.lng}, ${f.near.km} km)`);
  if (f.polygon && f.polygon.length >= 3 && f.polygon.length <= 20 && f.polygon.every((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng)))
    by.push(`location:(${f.polygon.map((p) => `${p.lat}, ${p.lng}`).join(', ')})`);

  const sort = {
    newest: 'featured:desc,updatedAt:desc',
    latest: 'updatedAt:desc',
    'price-asc': 'priceKES:asc',
    'price-desc': 'priceKES:desc',
    nearest: f.near ? `location(${f.near.lat}, ${f.near.lng}):asc` : 'updatedAt:desc',
  }[f.sort ?? 'newest'];

  return {
    q: f.q?.trim() || '*',
    // The description counts least: words in a title or area matter more.
    query_by: 'title,estate,area,amenities,description',
    query_by_weights: '4,3,3,2,1',
    filter_by: by.join(' && '),
    facet_by: 'type,beds,area,amenities,verified,priceKES',
    facet_stats_fields: 'priceKES',
    sort_by: f.verifiedFirst ? `verified:desc,${sort}` : sort,
    num_typos: 2,
    page: Math.max(1, f.page ?? 1),
    per_page: Math.min(50, Math.max(1, f.perPage ?? 20)),
  } as SearchParams<SearchDoc>;
}
