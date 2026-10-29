import type { Firestore } from 'firebase-admin/firestore';

/**
 * Saved-search alerts (D17, P4-s03). Every hour: the listings that went
 * live since the last sweep (`liveAt`), matched against every saved search;
 * each match becomes an alert in the owner's inbox (users/{uid}/alerts),
 * which the app shows. Email and push read the same alerts once their
 * senders are set up. One alert per search and listing (the id says so).
 */
export interface SearchFilters {
  purpose: string;
  types?: string[];
  areas?: string[];
  minBeds?: number;
  maxPriceKES?: number;
}

export interface LiveRow {
  id: string;
  slug: string;
  title: string;
  purpose: string;
  type: string;
  area: string;
  beds: number;
  priceKES: number;
}

export function matches(f: SearchFilters, l: LiveRow): boolean {
  return (
    l.purpose === f.purpose &&
    (!f.types?.length || f.types.includes(l.type)) &&
    (!f.areas?.length || f.areas.includes(l.area)) &&
    (f.minBeds == null || l.beds >= f.minBeds) &&
    (f.maxPriceKES == null || l.priceKES <= f.maxPriceKES)
  );
}

/** At most this many alerts per search and sweep, so a bulk import can't flood an inbox. */
export const MAX_ALERTS_PER_SEARCH = 10;

export async function sweepSavedSearches(db: Firestore, now = new Date()): Promise<{ listings: number; alerts: number }> {
  const stateRef = db.collection('config').doc('alerts');
  const since = ((await stateRef.get()).get('lastSweepAt')?.toDate() as Date | undefined) ?? new Date(now.getTime() - 3_600_000);
  const fresh = await db.collection('listings').where('status', '==', 'live').where('liveAt', '>', since).where('liveAt', '<=', now).get();
  let alerts = 0;
  if (!fresh.empty) {
    const rows: LiveRow[] = fresh.docs.map((d) => ({
      id: d.id,
      slug: d.get('slug'),
      title: d.get('title'),
      purpose: d.get('purpose'),
      type: d.get('type'),
      area: d.get('area'),
      beds: d.get('beds'),
      priceKES: d.get('priceKES'),
    }));
    const writer = db.bulkWriter();
    const searches = await db.collection('savedSearches').where('channels', 'array-contains', 'inbox').get();
    for (const s of searches.docs) {
      const hits = rows.filter((r) => matches(s.get('filters') as SearchFilters, r)).slice(0, MAX_ALERTS_PER_SEARCH);
      for (const r of hits) {
        const ref = db.collection('users').doc(s.get('userId')).collection('alerts').doc(`${s.id}_${r.id}`);
        void writer.set(ref, { searchId: s.id, listingId: r.id, slug: r.slug, title: r.title, priceKES: r.priceKES, purpose: r.purpose, area: r.area, createdAt: now, readAt: null });
        alerts++;
      }
      if (hits.length) void writer.update(s.ref, { lastNotifiedAt: now });
    }
    await writer.close();
  }
  await stateRef.set({ lastSweepAt: now }, { merge: true });
  return { listings: fresh.size, alerts };
}
