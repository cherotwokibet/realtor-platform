import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone, lead, leadChannel, leadStage } from '../model/schema';
import { type Caller, isManager, parseInput, requireStaff } from './auth';

/** How long a lead's personal data is kept (Data Protection Act 2019). Proposed: 24 months. */
export const LEAD_RETENTION_DAYS = 730;

export const createLeadInput = z.object({
  listingId: docId,
  channel: leadChannel,
  contact: z.object({ name: z.string().max(80).optional(), phone: kenyanPhone.optional(), email: z.email().optional() }),
  message: z.string().max(2000).optional(),
  /** The consent tick on the form. Without it nothing is stored. */
  consent: z.literal(true),
});

/** Anyone (signed in or not) can leave a lead on a live listing. */
export async function createLead(db: Firestore, input: unknown, now = new Date()): Promise<{ leadId: string }> {
  const req = parseInput(createLeadInput, input);
  const listingRef = db.collection('listings').doc(req.listingId);
  const leadRef = db.collection('leads').doc();
  await db.runTransaction(async (tx) => {
    const listing = await tx.get(listingRef);
    if (!listing.exists || listing.get('status') !== 'live') throw new HttpsError('not-found', 'listing is not available');
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
    tx.create(leadRef, doc);
    tx.update(listingRef, { 'stats.leads': FieldValue.increment(1) });
  });
  return { leadId: leadRef.id };
}

type Stage = z.infer<typeof leadStage>;
const NEXT: Record<Stage, Stage[]> = {
  new: ['contacted', 'lost'],
  contacted: ['viewing', 'offer', 'lost'],
  viewing: ['offer', 'won', 'lost'],
  offer: ['won', 'lost'],
  won: [],
  lost: ['contacted'],
};

export const canMoveLead = (from: Stage, to: Stage) => NEXT[from].includes(to);

export const updateLeadStageInput = z.object({ leadId: docId, stage: leadStage });

/** Agents move their own leads; managers move any. */
export async function updateLeadStage(db: Firestore, caller: Caller, input: unknown): Promise<{ stage: Stage }> {
  requireStaff(caller);
  const req = parseInput(updateLeadStageInput, input);
  const ref = db.collection('leads').doc(req.leadId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such lead');
    if (!isManager(caller) && snap.get('agentId') !== caller.agentId) throw new HttpsError('permission-denied', 'not your lead');
    const from = snap.get('stage') as Stage;
    if (!canMoveLead(from, req.stage)) throw new HttpsError('failed-precondition', `a lead cannot go from ${from} to ${req.stage}`);
    tx.update(ref, { stage: req.stage });
  });
  return { stage: req.stage };
}
