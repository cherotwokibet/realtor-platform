import type { Firestore } from 'firebase-admin/firestore';

/**
 * The live homes as one small file (P3-s01): what a results card needs and
 * nothing more, served at /api/listings.json through Hosting's CDN. The
 * customer app reads it on the web instead of starting the Firestore SDK
 * and reading every listing document, so the first results show seconds
 * sooner; index.html preloads it while the app itself downloads. Only
 * fields already public on a live listing are sent.
 */
export const INDEX_FIELDS = [
  'slug', 'title', 'purpose', 'type', 'beds', 'baths', 'priceKES', 'area', 'agentId', 'geo',
  'verifiedAt', 'expiresAt', 'featuredUntil', 'amenities', 'updatedAt',
] as const;

/** How long browsers and the CDN may keep it: fresh homes show within minutes. */
export const INDEX_CACHE = 'public, max-age=60, s-maxage=120';

/** At most this many homes, as the app's own Firestore read. */
export const INDEX_LIMIT = 2000;

/** Firestore Timestamps (anything with toMillis) as milliseconds; the rest as is. */
function plain(v: unknown): unknown {
  if (v && typeof v === 'object' && typeof (v as { toMillis?: unknown }).toMillis === 'function') return (v as { toMillis(): number }).toMillis();
  return v;
}

/** One media entry trimmed to what a card reads: its kind, the small copies, the photo's blurhash. */
function trimMedia(m: unknown): Record<string, unknown> | null {
  if (!m || typeof m !== 'object') return null;
  const e = m as Record<string, unknown>;
  const v = (e.variants ?? {}) as Record<string, unknown>;
  const variants: Record<string, unknown> = {};
  for (const k of ['card', 'thumb', 'poster']) if (typeof v[k] === 'string') variants[k] = v[k];
  const out: Record<string, unknown> = { kind: e.kind, variants };
  if (e.kind === 'photo' && typeof e.blurhash === 'string') out.blurhash = e.blurhash;
  return out;
}

/** A listing document as an index row: its id and the card's fields. */
export function indexRow(id: string, d: Record<string, unknown>): Record<string, unknown> {
  const row: Record<string, unknown> = { id };
  for (const k of INDEX_FIELDS) if (d[k] !== undefined && d[k] !== null) row[k] = plain(d[k]);
  if (Array.isArray(d.media)) row.media = d.media.map(trimMedia).filter((m) => m !== null);
  return row;
}

export async function listingIndex(db: Firestore, now = new Date()): Promise<{ at: number; rows: Record<string, unknown>[] }> {
  const snap = await db.collection('listings').where('status', '==', 'live').limit(INDEX_LIMIT).get();
  return { at: now.getTime(), rows: snap.docs.map((d) => indexRow(d.id, d.data())) };
}
