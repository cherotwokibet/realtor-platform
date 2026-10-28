/**
 * Retention (D12, DPA 2019): lead personal data is deleted once its
 * `retainUntil` has passed. Viewings carry the same client name and phone,
 * taken with the same consent at most a few days before the slot, so a
 * viewing goes when its slot is LEAD_RETENTION_DAYS old. Deleting, not
 * blanking: nothing else needs the rows (listing stats are counters).
 */
import type { Firestore, Query } from 'firebase-admin/firestore';
import { LEAD_RETENTION_DAYS } from './leads';

export interface PurgeResult {
  leads: number;
  viewings: number;
}

/** Deletes everything past retention at `now`, in pages of `page`. */
export async function purgeExpired(db: Firestore, now: Date, page = 300): Promise<PurgeResult> {
  const viewingCutoff = new Date(now.getTime() - LEAD_RETENTION_DAYS * 86_400_000);
  return {
    leads: await deleteAll(db, db.collection('leads').where('retainUntil', '<=', now), page),
    viewings: await deleteAll(db, db.collection('viewings').where('slot', '<=', viewingCutoff), page),
  };
}

async function deleteAll(db: Firestore, query: Query, page: number): Promise<number> {
  let deleted = 0;
  for (;;) {
    const snap = await query.limit(page).select().get();
    if (snap.empty) return deleted;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
    deleted += snap.size;
  }
}
