import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { z } from 'zod';
import { docId } from '../model/schema';
import { parseInput } from './auth';
import { checkLimits, LIMITS } from './ratelimit';

/**
 * Click-through on "Similar homes" (P7-s04): how often the section is shown
 * under a listing and how often one of its homes is opened, per Nairobi
 * day and surface. Counts only, in `stats/recommendations-YYYY-MM-DD`;
 * nothing about who looked. The monthly report adds the days up.
 */
export const recommendationInput = z.object({
  listingId: docId,
  event: z.enum(['shown', 'opened']),
  surface: z.enum(['app', 'web']),
});

/** `YYYY-MM-DD` in Nairobi (UTC+3 all year). */
export const nairobiDay = (t: Date) => new Date(t.getTime() + 3 * 3_600_000).toISOString().slice(0, 10);

export const recommendationDoc = (day: string) => `recommendations-${day}`;

export async function logRecommendation(db: Firestore, input: unknown, now = new Date()): Promise<{ counted: true }> {
  const req = parseInput(recommendationInput, input);
  const ref = db.collection('stats').doc(recommendationDoc(nairobiDay(now)));
  await db.runTransaction(async (tx) => {
    const count = await checkLimits(tx, db, [{ key: `rec:listing:${req.listingId}`, max: LIMITS.recommendationPerListing }], now);
    count();
    tx.set(ref, { day: nairobiDay(now), [req.surface]: { [req.event]: FieldValue.increment(1) } }, { merge: true });
  });
  return { counted: true };
}

export interface RecommendationTotals {
  shown: number;
  opened: number;
}

/** Shown and opened across [days] (`YYYY-MM-DD`, inclusive), both surfaces. */
export async function recommendationTotals(db: Firestore, firstDay: string, lastDay: string): Promise<RecommendationTotals> {
  const snap = await db
    .collection('stats')
    .where('__name__', '>=', db.collection('stats').doc(recommendationDoc(firstDay)))
    .where('__name__', '<=', db.collection('stats').doc(recommendationDoc(lastDay)))
    .get();
  const out = { shown: 0, opened: 0 };
  for (const d of snap.docs) {
    for (const surface of ['app', 'web']) {
      const s = (d.get(surface) ?? {}) as Partial<RecommendationTotals>;
      out.shown += s.shown ?? 0;
      out.opened += s.opened ?? 0;
    }
  }
  return out;
}
