/**
 * Rate limits on the public callables (P6-s05). Fixed one-hour windows kept
 * in `rateLimits/{sha256(key)}`, checked and counted inside the caller's own
 * transaction so a refused call writes nothing. Keys are per contact (phone
 * or email) and per listing; not per IP, because the share pages call these
 * from their own server, so every visitor would share one address.
 *
 * A counter holds no contact details: its id is a hash and it keeps only a
 * count and the window. Firestore's TTL policy on `expiresAt` deletes it.
 */
import { createHash } from 'node:crypto';
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

export interface Limit {
  key: string;
  max: number;
}

export const WINDOW_MS = 3_600_000;

/** Per hour. A real enquirer sends one or two; a listing rarely gets ten. */
export const LIMITS = {
  leadPerContact: 5,
  leadPerListing: 30,
  viewingPerPhone: 3,
  viewingPerListing: 20,
  tapPerListing: 300,
} as const;

const refFor = (db: Firestore, key: string) => db.collection('rateLimits').doc(createHash('sha256').update(key).digest('hex'));

/**
 * Reads every limit in `tx` and throws `resource-exhausted` if any is used
 * up. Returns the writes to make once the caller's own reads are done
 * (Firestore transactions need all reads before writes).
 */
export async function checkLimits(tx: Transaction, db: Firestore, limits: Limit[], now: Date): Promise<() => void> {
  const window = Math.floor(now.getTime() / WINDOW_MS) * WINDOW_MS;
  const refs = limits.map((l) => refFor(db, l.key));
  const snaps = await tx.getAll(...refs);
  const counts = snaps.map((s) => (s.exists && s.get('window') === window ? (s.get('count') as number) : 0));
  if (counts.some((c, i) => c >= limits[i].max)) throw new HttpsError('resource-exhausted', 'too many requests, try again in a while');
  return () => {
    refs.forEach((ref, i) => tx.set(ref, { window, count: counts[i] + 1, expiresAt: new Date(window + 2 * WINDOW_MS) }));
  };
}

/** The contact a lead is limited by: its phone, else its email (lowercased). */
export const contactKey = (c: { phone?: string; email?: string }) => (c.phone ? `phone:${c.phone}` : c.email ? `email:${c.email.toLowerCase()}` : null);
