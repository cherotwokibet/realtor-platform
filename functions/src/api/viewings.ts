import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone, lead, viewing } from '../model/schema';
import { parseInput } from './auth';
import { checkLimits, LIMITS } from './ratelimit';
import { LEAD_RETENTION_DAYS } from './leads';

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
