import { randomBytes } from 'node:crypto';
import type { DocumentReference, Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone } from '../model/schema';
import { type Caller, parseInput, requireManager } from '../api/auth';
import { MAX_FEATURE_DAYS } from '../api/listings';
import { tenantFeatures } from '../api/features';
import { type DarajaConfig, darajaToken, stkPush, stkQuery, type StkOutcome } from './daraja';

/**
 * M-Pesa payments (P6-s01). Only this file decides amounts and statuses;
 * clients read payments/{id} (managers) and their viewing's paymentId.
 *
 * - startViewingPayment: the viewing's fee, from the viewing (set by
 *   bookViewing), never from the client, and only to the phone that booked
 *   it, so nobody can aim a prompt at someone else's number. One payment per viewing
 *   (payments/viewing-fee_<viewingId>): a second tap within 2 minutes reuses
 *   the push already on the phone, and a paid viewing can't be paid twice.
 * - recordStkCallback: Safaricom's callback, matched by CheckoutRequestID
 *   and the payment's own random token in the callback URL. Repeats change
 *   nothing; an amount that differs from the payment is not marked paid.
 * - reconcilePayments: every few minutes, asks Daraja about pushes still
 *   pending after 3 minutes, so a lost callback never leaves money unrecorded.
 */

export interface PaymentDeps {
  daraja: DarajaConfig;
  /** The deployed mpesaCallback URL, without query. */
  callbackUrl: string;
  /** Price of one featured day (D20); null or absent switches featured-ad payments off. */
  featuredPerDayKES?: number | null;
  fetch?: typeof fetch;
}

const REUSE_PENDING_MS = 2 * 60_000;
export const RECONCILE_AFTER_MS = 3 * 60_000;
export const GIVE_UP_AFTER_MS = 24 * 3_600_000;

/** `phone` is accepted for older clients and ignored: the prompt goes to the booking phone. */
const startInput = z.object({ viewingId: docId, phone: kenyanPhone.optional() });

export async function startViewingPayment(
  db: Firestore,
  input: unknown,
  deps: PaymentDeps,
  now = new Date(),
): Promise<{ paymentId: string; status: 'pending' }> {
  const req = parseInput(startInput, input);
  const features = await tenantFeatures(db);
  if (features?.mpesa !== true) throw new HttpsError('failed-precondition', 'M-Pesa payments are not switched on for this realtor');

  const viewingRef = db.collection('viewings').doc(req.viewingId);
  const paymentRef = db.collection('payments').doc(`viewing-fee_${req.viewingId}`);
  const token = randomBytes(24).toString('hex');
  let amountKES = 0;
  let phone = '';
  let reuse = false;
  await db.runTransaction(async (tx) => {
    const [v, p] = await Promise.all([tx.get(viewingRef), tx.get(paymentRef)]);
    if (!v.exists || !['requested', 'confirmed'].includes(v.get('status'))) throw new HttpsError('not-found', 'that viewing is not open');
    amountKES = Number(v.get('feeKES') ?? 0);
    phone = String(v.get('client.phone') ?? '');
    if (!Number.isInteger(amountKES) || amountKES < 1) throw new HttpsError('failed-precondition', 'this viewing has no fee to pay');
    if (p.exists && p.get('status') === 'paid') throw new HttpsError('already-exists', 'this viewing fee is already paid');
    const created = p.exists ? (p.get('createdAt')?.toDate() as Date) : null;
    if (p.exists && p.get('status') === 'pending' && created && now.getTime() - created.getTime() < REUSE_PENDING_MS) {
      reuse = true;
      return;
    }
    tx.set(paymentRef, {
      purpose: 'viewing-fee',
      amountKES,
      phone,
      listingId: v.get('listingId'),
      viewingId: req.viewingId,
      checkoutRequestId: null,
      merchantRequestId: null,
      callbackToken: token,
      status: 'pending',
      receipt: null,
      reason: null,
      attempts: (p.exists ? Number(p.get('attempts') ?? 0) : 0) + 1,
      createdAt: now,
      updatedAt: now,
    });
  });
  if (reuse) return { paymentId: paymentRef.id, status: 'pending' };

  await sendPush(paymentRef, token, { amountKES, phone, accountReference: 'Viewing', description: 'Viewing fee' }, deps, now);
  return { paymentId: paymentRef.id, status: 'pending' };
}

/** Asks Daraja to prompt the phone; a refusal marks the payment failed. */
async function sendPush(
  paymentRef: DocumentReference,
  token: string,
  push: { amountKES: number; phone: string; accountReference: string; description: string },
  deps: PaymentDeps,
  now: Date,
): Promise<void> {
  try {
    const bearer = await darajaToken(deps.daraja, deps.fetch);
    const r = await stkPush(deps.daraja, bearer, { ...push, callbackUrl: `${deps.callbackUrl}?t=${token}` }, now, deps.fetch);
    await paymentRef.update({ checkoutRequestId: r.checkoutRequestId, merchantRequestId: r.merchantRequestId, updatedAt: now });
  } catch (e) {
    await paymentRef.update({ status: 'failed', reason: e instanceof Error ? e.message.slice(0, 200) : 'STK Push failed', updatedAt: now });
    throw new HttpsError('unavailable', 'M-Pesa did not take the request. Please try again in a minute.');
  }
}

const featuredInput = z.object({ listingId: docId, days: z.number().int().min(1).max(MAX_FEATURE_DAYS), phone: kenyanPhone });

/**
 * Featured-ad fee (D20): a manager pays for [days] of featuring a live
 * listing, from their own M-Pesa. The price is days x the project's
 * FEATURED_PER_DAY_KES, never from the client. The listing is featured only
 * when the payment settles as paid (see settle). Repeated taps within 2
 * minutes for the same listing, days and phone reuse the push already sent.
 */
export async function startFeaturedPayment(
  db: Firestore,
  caller: Caller,
  input: unknown,
  deps: PaymentDeps,
  now = new Date(),
): Promise<{ paymentId: string; amountKES: number; status: 'pending' }> {
  requireManager(caller);
  const req = parseInput(featuredInput, input);
  const features = await tenantFeatures(db);
  if (features?.mpesa !== true) throw new HttpsError('failed-precondition', 'M-Pesa payments are not switched on for this realtor');
  const perDay = deps.featuredPerDayKES;
  if (!perDay) throw new HttpsError('failed-precondition', 'featured-ad payments have no price set');
  const amountKES = perDay * req.days;

  const listing = await db.collection('listings').doc(req.listingId).get();
  if (!listing.exists || listing.get('status') !== 'live') throw new HttpsError('failed-precondition', 'only a live listing can be featured');

  const pending = await db
    .collection('payments')
    .where('listingId', '==', req.listingId)
    .where('purpose', '==', 'featured-ad')
    .where('status', '==', 'pending')
    .get();
  const open = pending.docs.find(
    (d) => d.get('days') === req.days && d.get('phone') === req.phone && now.getTime() - (d.get('createdAt').toDate() as Date).getTime() < REUSE_PENDING_MS,
  );
  if (open) return { paymentId: open.id, amountKES, status: 'pending' };

  const token = randomBytes(24).toString('hex');
  const paymentRef = db.collection('payments').doc(`featured-ad_${req.listingId}_${now.getTime()}`);
  await paymentRef.set({
    purpose: 'featured-ad',
    amountKES,
    phone: req.phone,
    listingId: req.listingId,
    days: req.days,
    requestedBy: caller.uid,
    checkoutRequestId: null,
    merchantRequestId: null,
    callbackToken: token,
    status: 'pending',
    receipt: null,
    reason: null,
    attempts: 1,
    createdAt: now,
    updatedAt: now,
  });
  await sendPush(paymentRef, token, { amountKES, phone: req.phone, accountReference: 'Featured', description: 'Featured listing' }, deps, now);
  return { paymentId: paymentRef.id, amountKES, status: 'pending' };
}

/** Applies an outcome to a pending payment (callback or query). Returns false when nothing changed. */
async function settle(db: Firestore, paymentId: string, outcome: StkOutcome, now: Date): Promise<boolean> {
  if (outcome.status === 'pending') return false;
  const ref = db.collection('payments').doc(paymentId);
  return db.runTransaction(async (tx) => {
    const p = await tx.get(ref);
    if (!p.exists || p.get('status') !== 'pending') return false;
    const featuring = outcome.status === 'paid' && p.get('purpose') === 'featured-ad' ? db.collection('listings').doc(String(p.get('listingId'))) : null;
    const listingSnap = featuring ? await tx.get(featuring) : null;
    if (outcome.status === 'paid') {
      const expected = Number(p.get('amountKES'));
      if (outcome.amountKES !== null && outcome.amountKES !== expected) {
        tx.update(ref, { status: 'failed', reason: `M-Pesa reported KES ${outcome.amountKES}, expected KES ${expected}: check by hand`, updatedAt: now });
        return true;
      }
      tx.update(ref, { status: 'paid', receipt: outcome.receipt, reason: null, updatedAt: now });
      const viewingId = p.get('viewingId') as string | undefined;
      if (viewingId) tx.update(db.collection('viewings').doc(viewingId), { paymentId: ref.id });
      if (featuring && listingSnap?.exists) {
        // Paid days add to any featuring still running; a listing taken down since stays down.
        const current = listingSnap.get('featuredUntil')?.toDate?.() as Date | undefined;
        const from = current && current > now ? current : now;
        if (listingSnap.get('status') === 'live') {
          tx.update(featuring, { featuredUntil: new Date(from.getTime() + Number(p.get('days')) * 86_400_000), updatedAt: now });
        } else {
          tx.update(ref, { reason: 'paid, but the listing is no longer live: not featured, refund by hand', updatedAt: now });
        }
      }
      return true;
    }
    tx.update(ref, { status: outcome.status, reason: outcome.reason.slice(0, 200), updatedAt: now });
    return true;
  });
}

/** Safaricom's callback. 'ignored' covers unknown pushes and wrong tokens, which get no detail back. */
export async function recordStkCallback(
  db: Firestore,
  callback: { checkoutRequestId: string; outcome: StkOutcome } | null,
  token: string | undefined,
  now = new Date(),
): Promise<'recorded' | 'ignored'> {
  if (!callback || !token) return 'ignored';
  const found = await db.collection('payments').where('checkoutRequestId', '==', callback.checkoutRequestId).limit(1).get();
  const p = found.docs[0];
  if (!p || p.get('callbackToken') !== token) return 'ignored';
  return (await settle(db, p.id, callback.outcome, now)) ? 'recorded' : 'ignored';
}

/** Pending pushes older than 3 minutes: ask Daraja; after 24 h with no answer, give up. */
export async function reconcilePayments(db: Firestore, deps: PaymentDeps, now = new Date()): Promise<{ checked: number; settled: number }> {
  const stale = await db
    .collection('payments')
    .where('status', '==', 'pending')
    .where('createdAt', '<', new Date(now.getTime() - RECONCILE_AFTER_MS))
    .limit(100)
    .get();
  if (stale.empty) return { checked: 0, settled: 0 };
  let bearer: string | null = null;
  let settled = 0;
  for (const p of stale.docs) {
    const age = now.getTime() - (p.get('createdAt').toDate() as Date).getTime();
    const checkout = p.get('checkoutRequestId') as string | null;
    let outcome: StkOutcome;
    if (!checkout) {
      outcome = { status: 'failed', reason: 'no STK Push was sent' };
    } else {
      try {
        bearer ??= await darajaToken(deps.daraja, deps.fetch);
        outcome = await stkQuery(deps.daraja, bearer, checkout, now, deps.fetch);
      } catch (e) {
        console.error(`reconcile ${p.id}: ${e instanceof Error ? e.message : e}`);
        outcome = { status: 'pending' };
      }
      if (outcome.status === 'pending' && age > GIVE_UP_AFTER_MS) outcome = { status: 'failed', reason: 'no answer from M-Pesa within 24 hours' };
    }
    if (await settle(db, p.id, outcome, now)) settled++;
  }
  return { checked: stale.size, settled };
}
