/** Keeps a tenant's Typesense collection in step with Firestore listings. */
import type { Client } from 'typesense';
import { collectionName, listingsSchema, toSearchDoc } from './schema';

const notFound = (e: unknown) => (e as { httpStatus?: number }).httpStatus === 404;

/** Creates the tenant's collection if it is missing. Safe to call on every cold start. */
export async function ensureCollection(client: Client, tenantId: string): Promise<void> {
  try {
    await client.collections(collectionName(tenantId)).retrieve();
  } catch (e) {
    if (!notFound(e)) throw e;
    await client.collections().create(listingsSchema(tenantId));
  }
}

/**
 * True when a write changed anything search cares about. Counters in
 * `stats` (views, leads, taps) change often and are not indexed.
 */
export function searchRelevantChange(before: Record<string, unknown> | undefined, after: Record<string, unknown> | undefined): boolean {
  if (!before || !after) return before !== after;
  const strip = ({ stats: _s, ...rest }: Record<string, unknown>) => rest;
  return JSON.stringify(strip(before), sortKeys) !== JSON.stringify(strip(after), sortKeys);
}

/** JSON.stringify replacer that orders object keys, so key order never counts as a change. */
function sortKeys(_k: string, v: unknown): unknown {
  if (!v || typeof v !== 'object' || Array.isArray(v) || v instanceof Date) return v;
  if (typeof (v as { toDate?: unknown }).toDate === 'function') return v;
  return Object.fromEntries(Object.entries(v as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
}

/** Upserts a live listing; removes anything that is no longer live (or deleted). */
export async function syncListing(
  client: Client,
  tenantId: string,
  id: string,
  after: Record<string, any> | undefined,
  now = new Date(),
): Promise<'upserted' | 'removed'> {
  const docs = client.collections(collectionName(tenantId)).documents();
  const doc = toSearchDoc(id, after, now);
  if (doc) {
    await docs.upsert(doc);
    return 'upserted';
  }
  try {
    await client.collections(collectionName(tenantId)).documents(id).delete();
  } catch (e) {
    if (!notFound(e)) throw e;
  }
  return 'removed';
}
