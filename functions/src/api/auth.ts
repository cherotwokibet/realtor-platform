import { HttpsError } from 'firebase-functions/v2/https';

/** Custom claims set on staff accounts (see firestore.rules). */
export interface Caller {
  uid: string | null;
  role: 'owner' | 'manager' | 'agent' | null;
  agentId: string | null;
  /** For the audit log: the account's display name or email. */
  name?: string | null;
}

export function callerFrom(auth: { uid: string; token: Record<string, unknown> } | undefined): Caller {
  const role = auth?.token.role;
  return {
    uid: auth?.uid ?? null,
    role: role === 'owner' || role === 'manager' || role === 'agent' ? role : null,
    agentId: typeof auth?.token.agentId === 'string' ? auth.token.agentId : null,
    name: typeof auth?.token.name === 'string' ? auth.token.name : typeof auth?.token.email === 'string' ? auth.token.email : null,
  };
}

export const isManager = (c: Caller) => c.role === 'owner' || c.role === 'manager';

export function requireStaff(c: Caller): void {
  if (!c.role) throw new HttpsError('permission-denied', 'staff only');
  if (c.role === 'agent' && !c.agentId) throw new HttpsError('permission-denied', 'agent account has no agentId');
}

export function requireOwner(c: Caller): void {
  if (c.role !== 'owner') throw new HttpsError('permission-denied', 'owner only');
}

export function requireManager(c: Caller): void {
  if (!isManager(c)) throw new HttpsError('permission-denied', 'owner or manager only');
}

/** Parses with zod and turns problems into an invalid-argument error. */
export function parseInput<T>(schema: { safeParse(v: unknown): { success: true; data: T } | { success: false; error: { issues: { path: PropertyKey[]; message: string }[] } } }, data: unknown): T {
  const r = schema.safeParse(data);
  if (!r.success) {
    const msg = r.error.issues.map((i) => `${i.path.join('.') || 'input'}: ${i.message}`).join('; ');
    throw new HttpsError('invalid-argument', msg);
  }
  return r.data;
}
