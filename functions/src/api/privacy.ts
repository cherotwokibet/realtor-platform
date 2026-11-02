/**
 * Data subject requests (DPA 2019 ss. 26, 40; P6-s04). An owner or manager
 * finds everything held about one person, by phone or email, in leads,
 * viewings and the reviews left after those viewings, and either exports
 * it or deletes it. Both are audited without
 * the person's details: an audit entry that kept the phone would undo the
 * deletion.
 */
import type { DocumentSnapshot, Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { kenyanPhone } from '../model/schema';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';
import { recomputeRating } from './reviews';

export const dataRequestInput = z
  .object({
    kind: z.enum(['export', 'delete']),
    phone: kenyanPhone.optional(),
    email: z.email().optional(),
  })
  .refine((r) => r.phone || r.email, { message: 'a phone or an email', path: ['phone'] });

export interface DataExport {
  leads: Record<string, unknown>[];
  viewings: Record<string, unknown>[];
  reviews: Record<string, unknown>[];
}

export type DataRequestResult =
  | { kind: 'export'; data: DataExport }
  | { kind: 'delete'; deleted: { leads: number; viewings: number; reviews: number } };

/** Timestamps become ISO strings so the export is plain JSON. */
function plain(d: DocumentSnapshot): Record<string, unknown> {
  const out: Record<string, unknown> = { id: d.id };
  for (const [k, v] of Object.entries(d.data() ?? {})) {
    out[k] = v && typeof (v as { toDate?: () => Date }).toDate === 'function' ? (v as { toDate(): Date }).toDate().toISOString() : v;
  }
  return out;
}

async function find(
  db: Firestore,
  phone?: string,
  email?: string,
): Promise<{ leads: DocumentSnapshot[]; viewings: DocumentSnapshot[]; reviews: DocumentSnapshot[] }> {
  const queries = [];
  if (phone) queries.push(db.collection('leads').where('contact.phone', '==', phone).get());
  // createLead stores emails lowercased; the form as typed covers older rows.
  if (email) queries.push(db.collection('leads').where('contact.email', 'in', [...new Set([email, email.toLowerCase()])]).get());
  const viewings = phone ? (await db.collection('viewings').where('client.phone', '==', phone).get()).docs : [];
  const byId = new Map<string, DocumentSnapshot>();
  for (const snap of await Promise.all(queries)) for (const d of snap.docs) byId.set(d.id, d);
  // Reviews carry no phone; they belong to the person through the viewing.
  const reviews: DocumentSnapshot[] = [];
  for (let i = 0; i < viewings.length; i += 30) {
    const ids = viewings.slice(i, i + 30).map((v) => v.id);
    reviews.push(...(await db.collection('reviews').where('viewingId', 'in', ids).get()).docs);
  }
  return { leads: [...byId.values()], viewings, reviews };
}

export async function dataRequest(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<DataRequestResult> {
  requireManager(caller);
  const req = parseInput(dataRequestInput, input);
  const found = await find(db, req.phone, req.email);
  const label = `${found.leads.length} leads, ${found.viewings.length} viewings, ${found.reviews.length} reviews`;
  if (found.leads.length + found.viewings.length + found.reviews.length > 450) throw new HttpsError('failed-precondition', `${label}: too many for one request, ask the developer`);

  const batch = db.batch();
  if (req.kind === 'delete') for (const d of [...found.leads, ...found.viewings, ...found.reviews]) batch.delete(d.ref);
  audit(batch, db, caller, { action: req.kind === 'export' ? 'privacy.export' : 'privacy.delete', target: { collection: 'people', id: 'request', label } }, now);
  await batch.commit();
  if (req.kind === 'delete') {
    // A deleted approved review no longer counts in its agent's rating.
    const agents = new Set(found.reviews.filter((r) => r.get('status') === 'approved').map((r) => r.get('agentId') as string));
    for (const agentId of agents) await recomputeRating(db, agentId);
  }

  return req.kind === 'export'
    ? { kind: 'export', data: { leads: found.leads.map(plain), viewings: found.viewings.map(plain), reviews: found.reviews.map(plain) } }
    : { kind: 'delete', deleted: { leads: found.leads.length, viewings: found.viewings.length, reviews: found.reviews.length } };
}
