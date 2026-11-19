import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { kenyanPhone } from '../model/schema';
import { type Caller, parseInput } from './auth';

/**
 * A customer's own profile (My account > Edit Profile): the name they go by
 * and the WhatsApp number agents may reach them on, in users/{uid}. Only the
 * signed-in customer writes their own; the number is checked here, not in
 * the app. Deleting the account removes the profile, saved searches, alerts
 * and push devices, then the sign-in itself.
 */
export const saveProfileInput = z.object({
  name: z.string().trim().min(2).max(80),
  // Empty clears it.
  whatsapp: z.union([kenyanPhone, z.literal('')]),
});

/** What the Function needs from Firebase Auth (a fake in tests). */
export interface CustomerAuth {
  setName(uid: string, name: string): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

function requireCustomer(c: Caller): string {
  if (!c.uid) throw new HttpsError('unauthenticated', 'sign in first');
  return c.uid;
}

export async function saveProfile(db: Firestore, auth: CustomerAuth, caller: Caller, input: unknown, now = new Date()) {
  const uid = requireCustomer(caller);
  const req = parseInput(saveProfileInput, input);
  await db.collection('users').doc(uid).set({ name: req.name, whatsapp: req.whatsapp || null, updatedAt: now }, { merge: true });
  await auth.setName(uid, req.name);
  return { name: req.name, whatsapp: req.whatsapp || null };
}

export async function deleteAccount(db: Firestore, auth: CustomerAuth, caller: Caller): Promise<{ deleted: boolean }> {
  const uid = requireCustomer(caller);
  // Staff accounts are removed by an owner (Staff screen), never from the app.
  if (caller.role) throw new HttpsError('failed-precondition', 'staff accounts are removed from the admin');
  const user = db.collection('users').doc(uid);
  const refs = [
    ...(await db.collection('savedSearches').where('userId', '==', uid).get()).docs.map((d) => d.ref),
    ...(await user.collection('alerts').get()).docs.map((d) => d.ref),
    ...(await user.collection('devices').get()).docs.map((d) => d.ref),
    user,
  ];
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    for (const r of refs.slice(i, i + 400)) batch.delete(r);
    await batch.commit();
  }
  await auth.deleteUser(uid);
  return { deleted: true };
}
