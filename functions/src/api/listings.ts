import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { canMove, type ListingStatus, verificationExpiry } from '../listing-rules';
import { geohash, slugify } from '../model/geo';
import { docId, kes, listing, listingPurpose, listingType, MAX_VIEWING_FEE_KES, mediaItem, slug } from '../model/schema';
import transitions from '../model/transitions.json';
import { audit } from './audit';
import { requirePurposeOn, tenantFeatures } from './features';
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
  viewingFeeKES: z.number().int().min(0).max(MAX_VIEWING_FEE_KES).optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  area: slug,
  estate: z.string().max(80).optional(),
  description: z.string().trim().max(3000).optional(),
  amenities: z.array(z.string().max(40)).max(40).default([]),
  utilities: z.object({ water: z.boolean(), electricity: z.boolean(), wifi: z.boolean() }).partial().default({}),
  /**
   * The listing's own photos and videos, in the order to show them. Only
   * entries the media pipeline added to this listing are accepted (matched by
   * their `full` or `hls` path) and the stored copy is kept, so a listing
   * can reorder or drop its media but never borrow another's. Leave it out
   * to keep the media as it is.
   */
  media: z.array(mediaItem).max(60).optional(),
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
  requirePurposeOn(await tenantFeatures(db), req.purpose);

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
    const { listingId: _id, lat, lng, agentId: _a, media: wanted, ...fields } = req;
    const stored = (existing.exists ? existing.get('media') ?? [] : []) as z.infer<typeof mediaItem>[];
    const doc = {
      ...fields,
      media: wanted === undefined ? stored : ownMedia(stored, wanted),
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
    audit(tx, db, caller, { action: 'listing.submit', target: { collection: 'listings', id: ref.id, label: req.title }, from, to: 'pending' }, now);
  });
  return { listingId: ref.id, slug: finalSlug };
}

const mediaKey = (m: { variants: Record<string, string> }) => m.variants.full ?? m.variants.hls ?? null;

/** [wanted] as entries of [stored], in the order asked for; anything else is refused. */
function ownMedia(stored: z.infer<typeof mediaItem>[], wanted: z.infer<typeof mediaItem>[]): z.infer<typeof mediaItem>[] {
  const byKey = new Map(stored.map((m) => [mediaKey(m), m]));
  const seen = new Set<string>();
  return wanted.map((m) => {
    const key = mediaKey(m);
    const own = key ? byKey.get(key) : undefined;
    if (!own || seen.has(key!)) throw new HttpsError('invalid-argument', "media: only this listing's own uploads, each once");
    seen.add(key!);
    return own;
  });
}

async function uniqueSlug(db: Firestore, base: string, id: string): Promise<string> {
  const taken = await db.collection('listings').where('slug', '==', base).limit(1).get();
  return taken.empty ? base : `${base}-${id.slice(0, 6).toLowerCase()}`.slice(0, 80);
}

const ACTION_TO: Record<'approve' | 'reject' | 'expire' | 'let' | 'sold', ListingStatus> = transitions.moderation as Record<
  'approve' | 'reject' | 'expire' | 'let' | 'sold',
  ListingStatus
>;

export const moderateListingInput = z
  .object({ listingId: docId, action: z.enum(['approve', 'reject', 'expire', 'let', 'sold']), reason: z.string().max(500).optional() })
  .refine((r) => r.action !== 'reject' || !!r.reason, { message: 'a rejection needs a reason', path: ['reason'] });

/** Managers approve (live + verified for 30 days), reject with a reason, or close a listing. */
export async function moderateListing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ status: ListingStatus }> {
  requireManager(caller);
  const req = parseInput(moderateListingInput, input);
  const ref = db.collection('listings').doc(req.listingId);
  const to = ACTION_TO[req.action];
  const features = to === 'live' ? await tenantFeatures(db) : null;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such listing');
    const from = snap.get('status') as ListingStatus;
    if (!canMove(from, to)) throw new HttpsError('failed-precondition', `a ${from} listing cannot be set to ${to}`);
    // A listing sent in before its purpose was switched off cannot go live.
    if (to === 'live') requirePurposeOn(features, snap.get('purpose'));
    tx.update(ref, {
      status: to,
      updatedAt: now,
      // liveAt: when it (re)joined the market; saved-search alerts look for it.
      ...(to === 'live' ? { verifiedAt: now, expiresAt: verificationExpiry(now), liveAt: now } : {}),
      ...(req.action === 'reject' ? { rejection: { reason: req.reason, at: now, by: caller.uid } } : {}),
    });
    audit(tx, db, caller, { action: `listing.${req.action}`, target: { collection: 'listings', id: ref.id, label: snap.get('title') as string | undefined }, from, to, reason: req.reason }, now);
  });
  return { status: to };
}

export const confirmListingInput = z.object({ listingId: docId });

/**
 * P6-s02: the listing's agent (or a manager) confirms it is still available
 * and its photos are current. A live or expired listing becomes live again,
 * verified for another VERIFICATION_DAYS.
 */
export async function confirmListing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ expiresAt: string }> {
  requireStaff(caller);
  const req = parseInput(confirmListingInput, input);
  const ref = db.collection('listings').doc(req.listingId);
  const expiresAt = verificationExpiry(now);
  const features = await tenantFeatures(db);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such listing');
    if (!isManager(caller) && snap.get('agentId') !== caller.agentId) throw new HttpsError('permission-denied', 'not your listing');
    const from = snap.get('status') as ListingStatus;
    if (from !== 'live' && from !== 'expired') throw new HttpsError('failed-precondition', `a ${from} listing cannot be confirmed`);
    requirePurposeOn(features, snap.get('purpose'));
    tx.update(ref, { status: 'live', verifiedAt: now, expiresAt, updatedAt: now, ...(from === 'expired' ? { liveAt: now } : {}) });
    audit(tx, db, caller, { action: 'listing.confirm', target: { collection: 'listings', id: ref.id, label: snap.get('title') as string | undefined }, from, to: 'live' }, now);
  });
  return { expiresAt: expiresAt.toISOString() };
}

/** The nightly job's name in the audit log. */
const NIGHTLY: Caller = { uid: null, role: null, agentId: null, name: 'Nightly expiry' };

/**
 * P6-s02: live listings whose verification has run out (expiresAt passed)
 * become expired, in pages; each move is audited. Returns how many moved.
 */
export async function expireListings(db: Firestore, now = new Date(), page = 200): Promise<number> {
  let moved = 0;
  for (;;) {
    const snap = await db.collection('listings').where('status', '==', 'live').where('expiresAt', '<=', now).limit(page).get();
    if (snap.empty) return moved;
    const batch = db.batch();
    for (const d of snap.docs) {
      batch.update(d.ref, { status: 'expired', updatedAt: now });
      audit(batch, db, NIGHTLY, { action: 'listing.expire', target: { collection: 'listings', id: d.id, label: d.get('title') as string | undefined }, from: 'live', to: 'expired' }, now);
    }
    await batch.commit();
    moved += snap.size;
  }
}

/** Clears featuredUntil once it has passed, so search re-syncs and stops ranking the listing first. */
export async function clearLapsedFeatures(db: Firestore, now = new Date()): Promise<number> {
  const snap = await db.collection('listings').where('featuredUntil', '<=', now).get();
  const batch = db.batch();
  for (const d of snap.docs) batch.update(d.ref, { featuredUntil: null });
  if (!snap.empty) await batch.commit();
  return snap.size;
}

/** Longest a listing can be featured in one go, in days. */
export const MAX_FEATURE_DAYS = 90;

export const featureListingInput = z.object({ listingId: docId, days: z.number().int().min(0).max(MAX_FEATURE_DAYS) });

/**
 * P5-s02: managers feature a live listing for [days] (it ranks first in
 * search until then), or stop featuring it with 0. Featured-ad fees by
 * M-Pesa come with P6-s01; this is the manual switch.
 */
export async function featureListing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ featuredUntil: string | null }> {
  requireManager(caller);
  const req = parseInput(featureListingInput, input);
  const ref = db.collection('listings').doc(req.listingId);
  const until = req.days ? new Date(now.getTime() + req.days * 86_400_000) : null;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such listing');
    if (until && snap.get('status') !== 'live') throw new HttpsError('failed-precondition', 'only a live listing can be featured');
    const before = snap.get('featuredUntil')?.toDate?.() as Date | undefined;
    tx.update(ref, { featuredUntil: until, updatedAt: now });
    audit(tx, db, caller, {
      action: 'listing.feature',
      target: { collection: 'listings', id: ref.id, label: snap.get('title') as string | undefined },
      from: before && before > now ? before.toISOString().slice(0, 10) : 'none',
      to: until ? until.toISOString().slice(0, 10) : 'none',
    }, now);
  });
  return { featuredUntil: until?.toISOString() ?? null };
}

/** Rows per importListings call; the admin sends bigger files in chunks. */
export const MAX_IMPORT_ROWS = 100;

export const importListingsInput = z.object({ rows: z.array(z.record(z.string(), z.unknown())).min(1).max(MAX_IMPORT_ROWS) });

export interface ImportResult {
  created: { row: number; listingId: string; slug: string }[];
  failed: { row: number; error: string }[];
}

/**
 * P5-s02 CSV bulk import: each row is a new listing, submitted exactly as
 * submitListing would (same validation, pending for review, audited), for
 * the agent the row names. One bad row does not stop the others; rows are
 * numbered from 1 as in the file (after its header).
 */
export async function importListings(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<ImportResult> {
  requireManager(caller);
  const { rows } = parseInput(importListingsInput, input);
  const agents = new Map<string, boolean>();
  const out: ImportResult = { created: [], failed: [] };
  for (const [i, row] of rows.entries()) {
    const n = i + 1;
    try {
      if ('listingId' in row || 'media' in row) throw new HttpsError('invalid-argument', 'import makes new listings only (no listingId or media)');
      const agentId = row.agentId;
      if (typeof agentId !== 'string' || !agentId) throw new HttpsError('invalid-argument', 'agentId: every row needs the agent');
      if (!agents.has(agentId)) agents.set(agentId, (await db.collection('agents').doc(agentId).get()).exists);
      if (!agents.get(agentId)) throw new HttpsError('invalid-argument', `agentId: no agent "${agentId}"`);
      const r = await submitListing(db, caller, row, now);
      out.created.push({ row: n, ...r });
    } catch (e) {
      out.failed.push({ row: n, error: e instanceof HttpsError ? e.message : 'could not be saved' });
    }
  }
  return out;
}

