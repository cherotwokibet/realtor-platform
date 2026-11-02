import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone, lead, viewing } from '../model/schema';
import { audit } from './audit';
import { type Caller, isManager, parseInput, requireStaff } from './auth';
import transitions from '../model/transitions.json';
import { checkLimits, LIMITS } from './ratelimit';
import { LEAD_RETENTION_DAYS } from './leads';
import { assertAgentFree } from './availability';
import { createReviewInvite } from './reviews';

/**
 * Viewing slots (P2-s03). Kenya is UTC+3 all year (no daylight saving), so
 * local time is plain arithmetic. Hours are the same for every tenant until
 * agent availability exists (P5 bookings & calendar).
 */
export const VIEWING_RULES = {
  utcOffsetHours: 3,
  slotMinutes: 30,
  /** First and last start times, local, in minutes after midnight. */
  firstStart: 8 * 60,
  lastStart: 17 * 60 + 30,
  /** Monday (1) to Saturday (6); no Sunday viewings. */
  days: [1, 2, 3, 4, 5, 6],
  minNoticeHours: 2,
  maxDaysAhead: 30,
};

/** Why a slot cannot be booked, or null when it can. Pure, unit-tested. */
export function slotProblem(slot: Date, now: Date): string | null {
  const r = VIEWING_RULES;
  if (Number.isNaN(slot.getTime())) return 'not a date';
  if (slot.getTime() < now.getTime() + r.minNoticeHours * 3_600_000) return `book at least ${r.minNoticeHours} hours ahead`;
  if (slot.getTime() > now.getTime() + r.maxDaysAhead * 86_400_000) return `book within ${r.maxDaysAhead} days`;
  const local = new Date(slot.getTime() + r.utcOffsetHours * 3_600_000);
  const minutes = local.getUTCHours() * 60 + local.getUTCMinutes();
  if (local.getUTCSeconds() || local.getUTCMilliseconds() || minutes % r.slotMinutes) return `slots start on the ${r.slotMinutes}-minute mark`;
  if (!r.days.includes(local.getUTCDay())) return 'no viewings on Sundays';
  if (minutes < r.firstStart || minutes > r.lastStart) return 'viewings run 8:00 to 18:00';
  return null;
}

export const bookViewingInput = z.object({
  listingId: docId,
  /** ISO 8601 with offset, e.g. 2026-10-27T10:30:00+03:00. */
  slot: z.iso.datetime({ offset: true }),
  client: z.object({ name: z.string().trim().min(1).max(80), phone: kenyanPhone }),
  message: z.string().max(2000).optional(),
  /** The consent tick: the client's name and phone become a lead (D12). */
  consent: z.literal(true),
});

const ACTIVE = new Set(['requested', 'confirmed']);

/**
 * Anyone can request a viewing of a live listing. One active booking per
 * agent per slot: the viewing id is `<agentId>_<slot ms>`, so a second
 * request for the same slot finds the first inside the transaction. The
 * client's details are also stored as a lead (channel `viewing`) so they
 * carry consent and retention like every other lead.
 */
export async function bookViewing(db: Firestore, input: unknown, now = new Date()): Promise<{ viewingId: string; leadId: string }> {
  const req = parseInput(bookViewingInput, input);
  const slot = new Date(req.slot);
  const problem = slotProblem(slot, now);
  if (problem) throw new HttpsError('invalid-argument', `slot: ${problem}`);

  const listingRef = db.collection('listings').doc(req.listingId);
  const leadRef = db.collection('leads').doc();
  let viewingId = '';
  await db.runTransaction(async (tx) => {
    const listing = await tx.get(listingRef);
    if (!listing.exists || listing.get('status') !== 'live') throw new HttpsError('not-found', 'listing is not available');
    const agentId = listing.get('agentId') as string;
    viewingId = `${agentId}_${slot.getTime()}`;
    const viewingRef = db.collection('viewings').doc(viewingId);
    const existing = await tx.get(viewingRef);
    if (existing.exists && ACTIVE.has(existing.get('status'))) throw new HttpsError('already-exists', 'that time is taken, pick another');
    await assertAgentFree(tx, db, agentId, slot, VIEWING_RULES.slotMinutes);
    const count = await checkLimits(
      tx,
      db,
      [
        { key: `viewing:phone:${req.client.phone}`, max: LIMITS.viewingPerPhone },
        { key: `viewing:listing:${req.listingId}`, max: LIMITS.viewingPerListing },
      ],
      now,
    );

    const v = {
      listingId: req.listingId,
      agentId,
      slot,
      client: req.client,
      status: 'requested' as const,
      feeKES: 0, // viewing fees by M-Pesa come with Daraja (P6)
      paymentId: null,
      createdAt: now,
    };
    const l = {
      listingId: req.listingId,
      agentId,
      channel: 'viewing' as const,
      contact: req.client,
      ...(req.message ? { message: req.message } : {}),
      stage: 'new' as const,
      consentAt: now,
      retainUntil: new Date(now.getTime() + LEAD_RETENTION_DAYS * 86_400_000),
      createdAt: now,
    };
    parseInput(viewing, v);
    parseInput(lead, l);
    count();
    tx.set(viewingRef, v);
    tx.create(leadRef, l);
    tx.update(listingRef, { 'stats.leads': FieldValue.increment(1) });
  });
  return { viewingId, leadId: leadRef.id };
}

type ViewingStatus = 'requested' | 'confirmed' | 'done' | 'no-show' | 'cancelled';
/** Allowed status moves, shared with the admin (model/transitions.json). */
const VIEWING_MOVES = transitions.viewingStatus as Record<ViewingStatus, ViewingStatus[]>;

export const updateViewingInput = z.object({
  viewingId: docId,
  status: z.enum(['confirmed', 'done', 'no-show', 'cancelled']),
});

/** "26 Oct, 10:30" in Nairobi time, for the audit label. */
const nairobi = (d: Date) =>
  d.toLocaleString('en-KE', { timeZone: 'Africa/Nairobi', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false });

/**
 * P5-s05: the viewing's agent (or a manager) confirms it, marks it done or
 * a no-show, or cancels it; a cancelled slot is free to book again. The
 * audit names the listing and time, never the client.
 */
export async function updateViewingStatus(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ status: ViewingStatus }> {
  requireStaff(caller);
  const req = parseInput(updateViewingInput, input);
  const ref = db.collection('viewings').doc(req.viewingId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such viewing');
    if (!isManager(caller) && snap.get('agentId') !== caller.agentId) throw new HttpsError('permission-denied', 'not your viewing');
    const from = snap.get('status') as ViewingStatus;
    if (!VIEWING_MOVES[from]?.includes(req.status)) throw new HttpsError('failed-precondition', `a ${from} viewing cannot become ${req.status}`);
    const slot = snap.get('slot').toDate() as Date;
    if ((req.status === 'done' || req.status === 'no-show') && slot > now) {
      throw new HttpsError('failed-precondition', 'the viewing has not happened yet');
    }
    const listing = await tx.get(db.collection('listings').doc(snap.get('listingId') as string));
    const title = listing.get('title') as string | undefined;
    // A done viewing gets its one-time review link (P6-s03).
    const reviewToken =
      req.status === 'done' ? createReviewInvite(tx, db, { id: ref.id, agentId: snap.get('agentId'), listingId: snap.get('listingId') }, now) : null;
    tx.update(ref, { status: req.status, updatedAt: now, ...(reviewToken ? { reviewToken } : {}) });
    audit(tx, db, caller, {
      action: 'viewing.status',
      target: { collection: 'viewings', id: ref.id, label: `Viewing${title ? ` of ${title}` : ''}, ${nairobi(slot)}` },
      from,
      to: req.status,
    }, now);
  });
  return { status: req.status };
}


export const rescheduleViewingInput = z.object({
  viewingId: docId,
  /** ISO 8601 with offset, e.g. 2026-10-29T15:00:00+03:00. */
  slot: z.iso.datetime({ offset: true }),
});

/**
 * P5-s05: the viewing's agent (or a manager) moves an open viewing to a new
 * time agreed with the client. The new time gets its own viewing (ids are
 * `<agentId>_<slot ms>`, so a clash with another active viewing of the same
 * agent is refused), confirmed; the old one is cancelled and points to it.
 */
export async function rescheduleViewing(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ viewingId: string }> {
  requireStaff(caller);
  const req = parseInput(rescheduleViewingInput, input);
  const slot = new Date(req.slot);
  const problem = slotProblem(slot, now);
  if (problem) throw new HttpsError('invalid-argument', `slot: ${problem}`);
  const oldRef = db.collection('viewings').doc(req.viewingId);
  let viewingId = '';
  await db.runTransaction(async (tx) => {
    const old = await tx.get(oldRef);
    if (!old.exists) throw new HttpsError('not-found', 'no such viewing');
    const agentId = old.get('agentId') as string;
    if (!isManager(caller) && agentId !== caller.agentId) throw new HttpsError('permission-denied', 'not your viewing');
    const from = old.get('status') as ViewingStatus;
    if (!ACTIVE.has(from)) throw new HttpsError('failed-precondition', `a ${from} viewing cannot be moved`);
    const oldSlot = old.get('slot').toDate() as Date;
    if (oldSlot.getTime() === slot.getTime()) throw new HttpsError('invalid-argument', 'slot: that is the time it already has');
    viewingId = `${agentId}_${slot.getTime()}`;
    const newRef = db.collection('viewings').doc(viewingId);
    const taken = await tx.get(newRef);
    if (taken.exists && ACTIVE.has(taken.get('status'))) throw new HttpsError('already-exists', 'the agent has another viewing then');
    await assertAgentFree(tx, db, agentId, slot, VIEWING_RULES.slotMinutes);
    const listing = await tx.get(db.collection('listings').doc(old.get('listingId') as string));
    const title = listing.get('title') as string | undefined;

    const moved = { ...old.data(), slot, status: 'confirmed' as const, rescheduledFrom: oldRef.id, createdAt: now, updatedAt: now };
    tx.set(newRef, moved);
    tx.update(oldRef, { status: 'cancelled', rescheduledTo: viewingId, updatedAt: now });
    audit(tx, db, caller, {
      action: 'viewing.reschedule',
      target: { collection: 'viewings', id: viewingId, label: `Viewing${title ? ` of ${title}` : ''}` },
      from: nairobi(oldSlot),
      to: nairobi(slot),
    }, now);
  });
  return { viewingId };
}

export const openSlotsInput = z.object({
  listingId: docId,
  /** Nairobi calendar day, e.g. 2026-10-30. */
  day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

/**
 * P4-s04: the times still bookable on [day] for a live listing's agent:
 * slot rules (notice, Sundays, hours), minus their active viewings and time
 * off. Only times are returned, never who booked. bookViewing still checks
 * in its transaction, so a race loses gracefully ("that time is taken").
 */
export async function openSlots(db: Firestore, input: unknown, now = new Date()): Promise<{ times: string[] }> {
  const req = parseInput(openSlotsInput, input);
  const listing = await db.collection('listings').doc(req.listingId).get();
  if (!listing.exists || listing.get('status') !== 'live') throw new HttpsError('not-found', 'listing is not available');
  const agentId = listing.get('agentId') as string;
  const r = VIEWING_RULES;
  const candidates: { time: string; slot: Date }[] = [];
  for (let m = r.firstStart; m <= r.lastStart; m += r.slotMinutes) {
    const time = `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
    const slot = new Date(`${req.day}T${time}:00+03:00`);
    if (!slotProblem(slot, now)) candidates.push({ time, slot });
  }
  if (!candidates.length) return { times: [] };
  const dayStart = candidates[0].slot, dayEnd = new Date(candidates.at(-1)!.slot.getTime() + r.slotMinutes * 60_000);
  const [viewings, blocks] = await Promise.all([
    db.getAll(...candidates.map((c) => db.collection('viewings').doc(`${agentId}_${c.slot.getTime()}`))),
    db.collection('agentBlocks').where('agentId', '==', agentId).where('end', '>', dayStart).orderBy('end').limit(50).get(),
  ]);
  const busy = new Set(viewings.filter((v) => v.exists && ACTIVE.has(v.get('status'))).map((v) => v.id));
  const off = blocks.docs.map((b) => ({ start: b.get('start').toDate() as Date, end: b.get('end').toDate() as Date })).filter((b) => b.start < dayEnd);
  return {
    times: candidates
      .filter((c) => !busy.has(`${agentId}_${c.slot.getTime()}`))
      .filter((c) => !off.some((b) => b.start.getTime() < c.slot.getTime() + r.slotMinutes * 60_000 && b.end > c.slot))
      .map((c) => c.time),
  };
}
