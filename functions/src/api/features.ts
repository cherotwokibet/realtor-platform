import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { z } from 'zod';
import type { listingPurpose } from '../model/schema';

/** The tenant file's `features` block, as stored in `config/tenant`. */
export type Features = Partial<Record<'sale' | 'rent' | 'shortStay' | 'offPlan' | 'mpesa' | 'ads' | 'aiSearch' | 'chat', boolean>>;

type Purpose = z.infer<typeof listingPurpose>;

const purposeFeature = { rent: 'rent', sale: 'sale', 'short-stay': 'shortStay' } as const satisfies Record<Purpose, keyof Features>;

/**
 * The tenant's switches from `config/tenant`, or null when that doc is not
 * there yet (D17: then nothing is switched off, as before the doc existed).
 */
export async function tenantFeatures(db: Firestore): Promise<Features | null> {
  const snap = await db.collection('config').doc('tenant').get();
  const f = snap.exists ? snap.get('features') : null;
  return f && typeof f === 'object' ? (f as Features) : null;
}

/** Only an explicit `false` switches a purpose off. */
export function purposeOn(features: Features | null, purpose: Purpose): boolean {
  return features?.[purposeFeature[purpose]] !== false;
}

export function requirePurposeOn(features: Features | null, purpose: Purpose): void {
  if (!purposeOn(features, purpose)) throw new HttpsError('failed-precondition', `${purpose} listings are switched off for this realtor`);
}
