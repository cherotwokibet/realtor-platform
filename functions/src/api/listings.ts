import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { canMove, type ListingStatus, verificationExpiry } from '../listing-rules';
import { geohash, slugify } from '../model/geo';
import { docId, kes, listing, listingPurpose, listingType, mediaItem, slug } from '../model/schema';
import { audit } from './audit';
import { type Caller, isManager, parseInput, requireManager, requireStaff } from './auth';

/** What an agent may send. Status, verification, slug, geohash and stats are set here. */
export const submitListingInput = z.object({
  listingId: docId.optional(),
  title: z.string().min(5).max(120),
  purpose: listingPurpose,
  type: listingType,
  beds: z.number().int().min(0).max(20),
  baths: z.number().int().min(0).max(20),
  priceKES: kes,
  depositMonths: z.number().int().min(0).max(12).optional(),
  serviceChargeKES: kes.optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  area: slug,
  estate: z.string().max(80).optional(),
  amenities: z.array(z.string().max(40)).max(40).default([]),
  utilities: z.object({ water: z.boolean(), electricity: z.boolean(), wifi: z.boolean() }).partial().default({}),
  media: z.array(mediaItem).max(60).default([]),
  /** Managers may submit for an agent; an agent always submits as themself. */
  agentId: docId.optional(),
});

/** Creates or edits a listing and sends it for review (status pending). */
export async function submitListing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ listingId: string; slug: string }> {
  requireStaff(caller);
  const req = parseInput(submitListingInput, input);
  const agentId = isManager(caller) ? req.agentId ?? caller.agentId : caller.agentId;
  if (!agentId) throw new HttpsError('invalid-argument', 'agentId is required');
  if (!(await db.collection('areas').doc(req.area).get()).exists) throw new HttpsError('invalid-argument', `unknown area ${req.area}`);

  const ref = req.listingId ? db.collection('listings').doc(req.listingId) : db.collection('listings').doc();
  const base = slugify(req.title);
  let finalSlug = '';
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      if (!isManager(caller) && existing.get('agentId') !== caller.agentId) throw new HttpsError('permission-denied', 'not your listing');
      const from = existing.get('status') as ListingStatus;
      if (from !== 'pending' && !canMove(from, 'pending') && from !== 'draft')
        throw new HttpsError('failed-precondition', `a ${from} listing cannot be resubmitted`);
    }
    finalSlug = existing.exists ? (existing.get('slug') as string) : await uniqueSlug(db, base, ref.id);
    const { listingId: _id, lat, lng, agentId: _a, ...fields } = req;
    const doc = {
      ...fields,
      slug: finalSlug,
      geo: { lat, lng, geohash: geohash(lat, lng) },
      agentId,
      status: 'pending' as const,
      verifiedAt: null,
      expiresAt: null,
      featuredUntil: existing.exists ? existing.get('featuredUntil') ?? null : null,
      stats: existing.exists ? existing.get('stats') : { views: 0, leads: 0 },
      createdAt: existing.exists ? existing.get('createdAt').toDate() : now,
      updatedAt: now,
    };
    parseInput(listing, doc);
    tx.set(ref, doc);
    const from = existing.exists ? (existing.get('status') as ListingStatus) : null;
    audit(tx, db, caller, { action: 'listing.submit', target: { collection: 'listings', id: ref.id }, from, to: 'pending' }, now);
  });
  return { listingId: ref.id, slug: finalSlug };
}

async function uniqueSlug(db: Firestore, base: string, id: string): Promise<string> {
  const taken = await db.collection('listings').where('slug', '==', base).limit(1).get();
  return taken.empty ? base : `${base}-${id.slice(0, 6).toLowerCase()}`.slice(0, 80);
}

const ACTION_TO: Record<'approve' | 'reject' | 'expire' | 'let' | 'sold', ListingStatus> = {
  approve: 'live',
  reject: 'draft',
  expire: 'expired',
  let: 'let',
  sold: 'sold',
};

export const moderateListingInput = z
  .object({ listingId: docId, action: z.enum(['approve', 'reject', 'expire', 'let', 'sold']), reason: z.string().max(500).optional() })
  .refine((r) => r.action !== 'reject' || !!r.reason, { message: 'a rejection needs a reason', path: ['reason'] });

/** Managers approve (live + verified for 30 days), reject with a reason, or close a listing. */
export async function moderateListing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ status: ListingStatus }> {
  requireManager(caller);
  const req = parseInput(moderateListingInput, input);
  const ref = db.collection('listings').doc(req.listingId);
  const to = ACTION_TO[req.action];
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such listing');
    const from = snap.get('status') as ListingStatus;
    if (!canMove(from, to)) throw new HttpsError('failed-precondition', `a ${from} listing cannot be set to ${to}`);
    tx.update(ref, {
      status: to,
      updatedAt: now,
      ...(to === 'live' ? { verifiedAt: now, expiresAt: verificationExpiry(now) } : {}),
      ...(req.action === 'reject' ? { rejection: { reason: req.reason, at: now, by: caller.uid } } : {}),
    });
    audit(tx, db, caller, { action: `listing.${req.action}`, target: { collection: 'listings', id: ref.id }, from, to, reason: req.reason }, now);
  });
  return { status: to };
}
