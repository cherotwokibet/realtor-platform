/**
 * Support and feedback. Anyone can send a question, a problem, feedback or
 * a complaint from the site (submitFeedback: public, App Check, rate
 * limited); managers work through them in the admin's Support inbox
 * (updateFeedback: status and notes, audited). A message's personal data
 * (name, phone, email) is kept as long as a lead's, and data requests find
 * and delete it the same way.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone } from '../model/schema';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';
import { LEAD_RETENTION_DAYS } from './leads';
import { checkLimits, contactKey, type Limit } from './ratelimit';

export const FEEDBACK_KINDS = ['question', 'problem', 'feedback', 'complaint'] as const;
export const FEEDBACK_STATUSES = ['new', 'open', 'resolved'] as const;

/** Per hour: one person rarely writes more; all of them together, a script would. */
export const FEEDBACK_LIMITS = { perContact: 5, overall: 200 } as const;

export const submitFeedbackInput = z.object({
  kind: z.enum(FEEDBACK_KINDS),
  message: z.string().trim().min(5).max(2000),
  name: z.string().trim().max(80).optional(),
  contact: z.object({ phone: kenyanPhone.optional(), email: z.email().transform((e) => e.toLowerCase()).optional() }).default({}),
  /** Where on the site it was sent from (a path), to see what it is about. */
  page: z.string().max(200).optional(),
});

export async function submitFeedback(db: Firestore, input: unknown, now = new Date()): Promise<{ feedbackId: string }> {
  const req = parseInput(submitFeedbackInput, input);
  const ref = db.collection('feedback').doc();
  const contact = contactKey(req.contact);
  const limits: Limit[] = [{ key: 'feedback:all', max: FEEDBACK_LIMITS.overall }];
  if (contact) limits.push({ key: `feedback:${contact}`, max: FEEDBACK_LIMITS.perContact });
  await db.runTransaction(async (tx) => {
    const count = await checkLimits(tx, db, limits, now);
    count();
    tx.create(ref, {
      kind: req.kind,
      message: req.message,
      ...(req.name ? { name: req.name } : {}),
      contact: req.contact,
      ...(req.page ? { page: req.page } : {}),
      status: 'new',
      notes: [],
      retainUntil: new Date(now.getTime() + LEAD_RETENTION_DAYS * 86_400_000),
      createdAt: now,
      updatedAt: now,
    });
  });
  return { feedbackId: ref.id };
}

export const updateFeedbackInput = z
  .object({
    feedbackId: docId,
    status: z.enum(FEEDBACK_STATUSES).optional(),
    /** Added to the message's notes (what was done, the reply sent). */
    note: z.string().trim().min(1).max(1000).optional(),
  })
  .refine((r) => r.status || r.note, { message: 'a status or a note', path: ['status'] });

export async function updateFeedback(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ status: string }> {
  requireManager(caller);
  const req = parseInput(updateFeedbackInput, input);
  const ref = db.collection('feedback').doc(req.feedbackId);
  let status = '';
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such message');
    const from = snap.get('status') as string;
    status = req.status ?? from;
    tx.update(ref, {
      status,
      updatedAt: now,
      ...(req.note ? { notes: FieldValue.arrayUnion({ text: req.note, by: caller.name ?? null, at: now }) } : {}),
    });
    // The audit keeps no message text or contact details.
    audit(tx, db, caller, { action: 'feedback.update', target: { collection: 'feedback', id: ref.id, label: snap.get('kind') as string }, from, to: status }, now);
  });
  return { status };
}
