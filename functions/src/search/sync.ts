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
