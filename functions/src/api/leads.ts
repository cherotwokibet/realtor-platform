import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone, lead, leadChannel, leadStage } from '../model/schema';
import transitions from '../model/transitions.json';
import { audit } from './audit';
import { type Caller, isManager, parseInput, requireStaff } from './auth';
import { checkLimits, contactKey, LIMITS, type Limit } from './ratelimit';

/** How long a lead's personal data is kept (Data Protection Act 2019). Proposed: 24 months. */
export const LEAD_RETENTION_DAYS = 730;

export const createLeadInput = z.object({
  listingId: docId,
  channel: leadChannel,
  // Emails are stored lowercased, so data requests and rate limits find every lead of one address.
  contact: z.object({ name: z.string().max(80).optional(), phone: kenyanPhone.optional(), email: z.email().toLowerCase().optional() }),
  message: z.string().max(2000).optional(),
  /** The consent tick on the form. Without it nothing is stored. */
  consent: z.literal(true),
});

/** Anyone (signed in or not) can leave a lead on a live listing. */
export async function createLead(db: Firestore, input: unknown, now = new Date()): Promise<{ leadId: string }> {
  const req = parseInput(createLeadInput, input);
  const listingRef = db.collection('listings').doc(req.listingId);
  const leadRef = db.collection('leads').doc();
  const contact = contactKey(req.contact);
  const limits: Limit[] = [{ key: `lead:listing:${req.listingId}`, max: LIMITS.leadPerListing }];
  if (contact) limits.push({ key: `lead:${contact}`, max: LIMITS.leadPerContact });
  await db.runTransaction(async (tx) => {
    const listing = await tx.get(listingRef);
    if (!listing.exists || listing.get('status') !== 'live') throw new HttpsError('not-found', 'listing is not available');
    const count = await checkLimits(tx, db, limits, now);
    const doc = {
      listingId: req.listingId,
      agentId: listing.get('agentId') as string,
      channel: req.channel,
      contact: req.contact,
      ...(req.message ? { message: req.message } : {}),
      stage: 'new' as const,
      consentAt: now,
      retainUntil: new Date(now.getTime() + LEAD_RETENTION_DAYS * 86_400_000),
      createdAt: now,
    };
    parseInput(lead, doc); // e.g. needs a phone or an email
    count();
    tx.create(leadRef, doc);
    tx.update(listingRef, { 'stats.leads': FieldValue.increment(1) });
  });
  return { leadId: leadRef.id };
}

export const contactTapInput = z.object({ listingId: docId, channel: z.enum(['call', 'whatsapp']) });

/**
 * A call or WhatsApp tap (D13). It carries no contact details, so it is
 * counted on the listing instead of stored as a lead; the conversation
 * itself happens on the phone or in WhatsApp.
 */
export async function logContactTap(db: Firestore, input: unknown, now = new Date()): Promise<{ counted: true }> {
  const req = parseInput(contactTapInput, input);
  const ref = db.collection('listings').doc(req.listingId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get('status') !== 'live') throw new HttpsError('not-found', 'listing is not available');
    const count = await checkLimits(tx, db, [{ key: `tap:listing:${req.listingId}`, max: LIMITS.tapPerListing }], now);
    count();
    tx.update(ref, { [`stats.${req.channel === 'call' ? 'calls' : 'whatsapps'}`]: FieldValue.increment(1) });
  });
  return { counted: true };
}

type Stage = z.infer<typeof leadStage>;
/** Allowed stage moves, shared with the admin's menus (packages/core checks it reads the same file). */
const NEXT: Record<Stage, readonly Stage[]> = transitions.leadStage as Record<Stage, Stage[]>;

export const canMoveLead = (from: Stage, to: Stage) => NEXT[from].includes(to);

export const updateLeadStageInput = z.object({ leadId: docId, stage: leadStage });

/** Agents move their own leads; managers move any. */
export async function updateLeadStage(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ stage: Stage }> {
  requireStaff(caller);
  const req = parseInput(updateLeadStageInput, input);
  const ref = db.collection('leads').doc(req.leadId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such lead');
    if (!isManager(caller) && snap.get('agentId') !== caller.agentId) throw new HttpsError('permission-denied', 'not your lead');
    const from = snap.get('stage') as Stage;
    if (!canMoveLead(from, req.stage)) throw new HttpsError('failed-precondition', `a lead cannot go from ${from} to ${req.stage}`);
    // The audit log names the lead by its listing, not by the person (no personal data there).
    const listingId = snap.get('listingId') as string | null;
    const listing = listingId ? await tx.get(db.collection('listings').doc(listingId)) : null;
    const title = listing?.get('title') as string | undefined;
    tx.update(ref, { stage: req.stage });
    audit(tx, db, caller, { action: 'lead.stage', target: { collection: 'leads', id: ref.id, label: title ? `Lead on ${title}` : undefined }, from, to: req.stage }, now);
  });
  return { stage: req.stage };
}
