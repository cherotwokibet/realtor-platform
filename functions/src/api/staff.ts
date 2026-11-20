import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone } from '../model/schema';
import { audit } from './audit';
import { type Caller, parseInput, requireOwner, requireStaff } from './auth';

type Role = 'owner' | 'manager' | 'agent';

/** The parts of firebase-admin's Auth this needs (a fake in tests). */
export interface StaffAuth {
  getUserByEmail(email: string): Promise<{ uid: string; email?: string; displayName?: string; customClaims?: Record<string, unknown> }>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown> | null): Promise<void>;
  updateUser(uid: string, props: { displayName?: string }): Promise<unknown>;
}

export const setStaffRoleInput = z
  .object({
    email: z.email(),
    /** null removes the account from staff. */
    role: z.enum(['owner', 'manager', 'agent']).nullable(),
    agentId: docId.optional(),
  })
  .refine((r) => r.role !== 'agent' || !!r.agentId, { message: 'an agent needs an agentId', path: ['agentId'] });

/**
 * Owners give an existing account a staff role (or take it away). The role is
 * a custom claim, which firestore.rules and the callables read; staff/{uid}
 * mirrors it so the admin can list the team. The person must have signed in
 * once, so their account exists: no accounts or passwords are made here.
 * Claims reach the client on its next token refresh.
 */
export async function setStaffRole(db: Firestore, auth: StaffAuth, caller: Caller, input: unknown, now = new Date()): Promise<{ uid: string; role: Role | null }> {
  requireOwner(caller);
  const req = parseInput(setStaffRoleInput, input);
  const user = await userByEmail(auth, req.email);
  if (user.uid === caller.uid && req.role !== 'owner') throw new HttpsError('failed-precondition', 'an owner cannot remove their own owner role');
  await applyRole(db, auth, caller, user, req.role, req.role === 'agent' ? req.agentId! : null, now);
  return { uid: user.uid, role: req.role };
}

/**
 * Makes the first owner of a new tenant, from a trusted script (staff/owner.ts).
 * Refused once any owner exists: after that, owners use setStaffRole.
 */
export async function bootstrapOwner(db: Firestore, auth: StaffAuth, email: string, now = new Date()): Promise<{ uid: string }> {
  const owners = await db.collection('staff').where('role', '==', 'owner').limit(1).get();
  if (!owners.empty) throw new HttpsError('failed-precondition', 'this project already has an owner: use setStaffRole');
  const user = await userByEmail(auth, z.email().parse(email));
  await applyRole(db, auth, { uid: null, role: null, agentId: null, name: 'owner bootstrap script' }, user, 'owner', null, now);
  return { uid: user.uid };
}

async function userByEmail(auth: StaffAuth, email: string) {
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if ((e as { code?: string }).code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'no account with that email: ask them to sign in to the admin once first');
    }
    throw e;
  }
}

async function applyRole(
  db: Firestore,
  auth: StaffAuth,
  caller: Caller,
  user: Awaited<ReturnType<StaffAuth['getUserByEmail']>>,
  role: Role | null,
  agentId: string | null,
  now: Date,
): Promise<void> {
  if (agentId && !(await db.collection('agents').doc(agentId).get()).exists) throw new HttpsError('invalid-argument', `unknown agent ${agentId}`);
  const { role: prev, agentId: _a, ...other } = user.customClaims ?? {};
  await auth.setCustomUserClaims(user.uid, { ...other, ...(role ? { role } : {}), ...(agentId ? { agentId } : {}) });
  const batch = db.batch();
  const ref = db.collection('staff').doc(user.uid);
  if (role) batch.set(ref, { email: user.email ?? null, name: user.displayName ?? null, role, agentId, updatedAt: now });
  else batch.delete(ref);
  audit(batch, db, caller, { action: 'staff.role', target: { collection: 'staff', id: user.uid, label: user.email }, from: typeof prev === 'string' ? prev : null, to: role ?? 'none' }, now);
  await batch.commit();
}

export const saveStaffProfileInput = z.object({
  name: z.string().trim().min(2).max(80),
  /** E.164 Kenyan mobile; null clears it. */
  phone: kenyanPhone.nullable().optional(),
});

/**
 * Any staff member's own name and phone (Account). The name is also the
 * account's display name, which the audit log shows; staff/{uid} keeps both
 * for the team list and its search.
 */
export async function saveStaffProfile(db: Firestore, auth: StaffAuth, caller: Caller, input: unknown, now = new Date()): Promise<{ ok: true }> {
  requireStaff(caller);
  const req = parseInput(saveStaffProfileInput, input);
  const ref = db.collection('staff').doc(caller.uid!);
  if (!(await ref.get()).exists) throw new HttpsError('failed-precondition', 'no staff record for this account yet');
  await auth.updateUser(caller.uid!, { displayName: req.name });
  await ref.set({ name: req.name, phone: req.phone ?? null, updatedAt: now }, { merge: true });
  return { ok: true };
}
