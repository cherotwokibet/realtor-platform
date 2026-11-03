import { randomBytes } from 'node:crypto';
import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone } from '../model/schema';
import { parseInput } from '../api/auth';
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

  try {
    const bearer = await darajaToken(deps.daraja, deps.fetch);
    const r = await stkPush(
      deps.daraja,
      bearer,
      {
        amountKES,
        phone,
        callbackUrl: `${deps.callbackUrl}?t=${token}`,
        accountReference: 'Viewing',
        description: 'Viewing fee',
      },
      now,
      deps.fetch,
    );
    await paymentRef.update({ checkoutRequestId: r.checkoutRequestId, merchantRequestId: r.merchantRequestId, updatedAt: now });
  } catch (e) {
    await paymentRef.update({ status: 'failed', reason: e instanceof Error ? e.message.slice(0, 200) : 'STK Push failed', updatedAt: now });
    throw new HttpsError('unavailable', 'M-Pesa did not take the request. Please try again in a minute.');
  }
  return { paymentId: paymentRef.id, status: 'pending' };
}

/** Applies an outcome to a pending payment (callback or query). Returns false when nothing changed. */
async function settle(db: Firestore, paymentId: string, outcome: StkOutcome, now: Date): Promise<boolean> {
  if (outcome.status === 'pending') return false;
  const ref = db.collection('payments').doc(paymentId);
  return db.runTransaction(async (tx) => {
    const p = await tx.get(ref);
    if (!p.exists || p.get('status') !== 'pending') return false;
    if (outcome.status === 'paid') {
      const expected = Number(p.get('amountKES'));
      if (outcome.amountKES !== null && outcome.amountKES !== expected) {
        tx.update(ref, { status: 'failed', reason: `M-Pesa reported KES ${outcome.amountKES}, expected KES ${expected}: check by hand`, updatedAt: now });
        return true;
      }
      tx.update(ref, { status: 'paid', receipt: outcome.receipt, reason: null, updatedAt: now });
      const viewingId = p.get('viewingId') as string | undefined;
      if (viewingId) tx.update(db.collection('viewings').doc(viewingId), { paymentId: ref.id });
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
