import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { canMove, type ListingStatus, verificationExpiry } from '../listing-rules';
import { geohash, insidePolygon, slugify } from '../model/geo';
import { docId, extraCharge, kes, listing, listingPurpose, listingType, MAX_VIEWING_FEE_KES, mediaItem, slug } from '../model/schema';
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
  extraCharges: z.array(extraCharge).max(10).optional(),
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
/**
 * What a listing says (the part an edit changes); everything else (status,
 * verification, placements, stats, slug) stays as it is when a live listing
 * is edited.
 */
const CONTENT_KEYS = [
  'title', 'purpose', 'type', 'beds', 'baths', 'priceKES', 'depositMonths', 'serviceChargeKES', 'viewingFeeKES',
  'geo', 'area', 'estate', 'description', 'amenities', 'extraCharges', 'utilities', 'media', 'agentId',
] as const;

/** [data] without its content, so content left out of an edit is removed rather than kept. */
function withoutContent(data: Record<string, unknown>): Record<string, unknown> {
  const out = { ...data };
  for (const k of CONTENT_KEYS) delete out[k];
  return out;
}

/** A copy of [data] with Firestore Timestamps as Dates, to check against the schema. */
function asDates(data: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) {
    out[k] = v && typeof v === 'object' && typeof (v as { toDate?: unknown }).toDate === 'function' ? (v as { toDate(): Date }).toDate() : v;
  }
  return out;
}

/** Which content fields differ between [before] and [after] (for the audit log and the review). */
export function changedFields(before: Record<string, unknown>, after: Record<string, unknown>): string[] {
  return CONTENT_KEYS.filter((k) => JSON.stringify(before[k] ?? null) !== JSON.stringify(after[k] ?? null));
}

/**
 * Creates or edits a listing. New, draft, pending and closed listings go to
 * pending for review, as before. A live listing stays live: a manager's edit
 * applies at once, an agent's becomes an edit request (listingEdits/{id},
 * one per listing) that a manager approves or rejects (moderateEdit).
 */
export async function submitListing(
  db: Firestore,
  caller: Caller,
  input: unknown,
  now = new Date(),
): Promise<{ listingId: string; slug: string; editRequest?: boolean; changed?: string[] }> {
  requireStaff(caller);
  const req = parseInput(submitListingInput, input);
  const agentId = isManager(caller) ? req.agentId ?? caller.agentId : caller.agentId;
  if (!agentId) throw new HttpsError('invalid-argument', 'agentId is required');
  const area = await db.collection('areas').doc(req.area).get();
  if (!area.exists) throw new HttpsError('invalid-argument', `unknown area ${req.area}`);
  // Geofence: an area with an outline only takes pins inside it.
  const outline = area.get('boundary') as { lat: number; lng: number }[] | null | undefined;
  if (outline && outline.length >= 3 && !insidePolygon(req.lat, req.lng, outline)) {
    throw new HttpsError('invalid-argument', `location: the pin is outside ${area.get('name') ?? req.area}. Move it, or pick the area it is in`);
  }
  requirePurposeOn(await tenantFeatures(db), req.purpose);

  const ref = req.listingId ? db.collection('listings').doc(req.listingId) : db.collection('listings').doc();
  const base = slugify(req.title);
  let finalSlug = '';
  let editRequest = false;
  let changed: string[] | undefined;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists && existing.get('status') === 'live') {
      if (!isManager(caller) && existing.get('agentId') !== caller.agentId) throw new HttpsError('permission-denied', 'not your listing');
      const { listingId: _id, lat, lng, agentId: _a, media: wanted, ...fields } = req;
      const before = existing.data() as Record<string, unknown>;
      const stored = (before.media ?? []) as z.infer<typeof mediaItem>[];
      const content: Record<string, unknown> = {
        ...fields,
        media: wanted === undefined ? stored : ownMedia(stored, wanted),
        geo: { lat, lng, geohash: geohash(lat, lng) },
        agentId,
      };
      const merged = { ...withoutContent(before), ...content, updatedAt: now };
      parseInput(listing, asDates(merged));
      changed = changedFields(before, content);
      finalSlug = before.slug as string;
      const target = { collection: 'listings' as const, id: ref.id, label: before.title as string | undefined };
      if (isManager(caller)) {
        tx.set(ref, merged);
        audit(tx, db, caller, { action: 'listing.edit', target, from: 'live', to: 'live', reason: changed.join(', ') || undefined }, now);
      } else {
        editRequest = true;
        tx.set(db.collection('listingEdits').doc(ref.id), {
          listingId: ref.id,
          agentId,
          title: before.title,
          proposed: content,
          changed,
          status: 'pending',
          submittedAt: now,
          submittedBy: caller.name ?? null,
        });
        audit(tx, db, caller, { action: 'listing.edit-request', target, from: 'live', to: 'pending edit', reason: changed.join(', ') || undefined }, now);
      }
      return;
    }
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
  return { listingId: ref.id, slug: finalSlug, ...(editRequest ? { editRequest } : {}), ...(changed ? { changed } : {}) };
}

export const moderateEditInput = z
  .object({ listingId: docId, action: z.enum(['approve', 'reject']), reason: z.string().max(500).optional() })
  .refine((r) => r.action !== 'reject' || !!r.reason, { message: 'a rejection needs a reason', path: ['reason'] });

/** Managers apply an agent's pending edit to the listing (it stays as it is otherwise), or reject it with a reason. */
export async function moderateEdit(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ status: 'approved' | 'rejected' }> {
  requireManager(caller);
  const req = parseInput(moderateEditInput, input);
  const editRef = db.collection('listingEdits').doc(req.listingId);
  const ref = db.collection('listings').doc(req.listingId);
  await db.runTransaction(async (tx) => {
    const [edit, snap] = [await tx.get(editRef), await tx.get(ref)];
    if (!edit.exists || edit.get('status') !== 'pending') throw new HttpsError('not-found', 'no edit waiting for this listing');
    if (!snap.exists) throw new HttpsError('not-found', 'no such listing');
    const target = { collection: 'listings' as const, id: ref.id, label: snap.get('title') as string | undefined };
    if (req.action === 'approve') {
      const before = snap.data() as Record<string, unknown>;
      const merged = { ...withoutContent(before), ...(edit.get('proposed') as Record<string, unknown>), updatedAt: now };
      tx.set(ref, merged);
      tx.update(editRef, { status: 'approved', decidedAt: now, decidedBy: caller.name ?? null });
      audit(tx, db, caller, { action: 'listing.edit-approve', target, from: 'pending edit', to: 'applied' }, now);
    } else {
      tx.update(editRef, { status: 'rejected', reason: req.reason, decidedAt: now, decidedBy: caller.name ?? null });
      audit(tx, db, caller, { action: 'listing.edit-reject', target, from: 'pending edit', to: 'rejected', reason: req.reason }, now);
    }
  });
  return { status: req.action === 'approve' ? 'approved' : 'rejected' };
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

/** The home page's rows a manager places a listing in, and the field that says so. */
export const PLACEMENT_FIELDS = { hot: 'hot', recommended: 'recommended', newest: 'pinnedNewest' } as const;
const PLACEMENT_AUDIT = { hot: 'listing.hot', recommended: 'listing.recommend', newest: 'listing.pin-newest' } as const;

export const setPlacementInput = z.object({ listingId: docId, placement: z.enum(['hot', 'recommended', 'newest']), on: z.boolean() });

/**
 * Managers put a live listing in a home page row (Hot properties,
 * Recommended, or pinned first in Newest), or take it out. Featured has its
 * own end date (featureListing). The customer app only reads the flags.
 */
export async function setPlacement(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ on: boolean }> {
  requireManager(caller);
  const req = parseInput(setPlacementInput, input);
  const field = PLACEMENT_FIELDS[req.placement];
  const ref = db.collection('listings').doc(req.listingId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such listing');
    if (req.on && snap.get('status') !== 'live') throw new HttpsError('failed-precondition', 'only a live listing can be placed on the home page');
    tx.update(ref, { [field]: req.on, updatedAt: now });
    audit(tx, db, caller, {
      action: PLACEMENT_AUDIT[req.placement],
      target: { collection: 'listings', id: ref.id, label: snap.get('title') as string | undefined },
      from: snap.get(field) === true ? req.placement : 'none',
      to: req.on ? req.placement : 'none',
    }, now);
  });
  return { on: req.on };
}

export const setHotListingInput = z.object({ listingId: docId, hot: z.boolean() });

/** Hot Properties on or off: setPlacement for `hot`, kept for older admins. */
export async function setHotListing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ hot: boolean }> {
  const req = parseInput(setHotListingInput, input);
  await setPlacement(db, caller, { listingId: req.listingId, placement: 'hot', on: req.hot }, now);
  return { hot: req.hot };
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

