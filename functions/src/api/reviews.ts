import { randomBytes } from 'node:crypto';
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId } from '../model/schema';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';

/**
 * Reviews (P6-s03). A viewing marked done gets a one-time review link
 * (`reviewInvites/{token}`, 30 days); the agent sends it to the client on
 * WhatsApp from the admin. The client rates the agent 1-5 on the share
 * pages; a manager approves the review before it shows, and approving or
 * hiding recomputes the agent's rating from approved reviews only.
 * Reviews keep a first name at most, never a phone number.
 */
export const REVIEW_INVITE_DAYS = 30;

/** Called inside updateViewingStatus's transaction when a viewing is done. */
export function createReviewInvite(tx: Transaction, db: Firestore, viewing: { id: string; agentId: string; listingId: string }, now: Date): string {
  const token = randomBytes(18).toString('base64url');
  tx.create(db.collection('reviewInvites').doc(token), {
    viewingId: viewing.id,
    agentId: viewing.agentId,
    listingId: viewing.listingId,
    expiresAt: new Date(now.getTime() + REVIEW_INVITE_DAYS * 86_400_000),
    usedAt: null,
    createdAt: now,
  });
  return token;
}

export const submitReviewInput = z.object({
  token: z.string().regex(/^[A-Za-z0-9_-]{20,40}$/),
  rating: z.number().int().min(1).max(5),
  comment: z.string().trim().max(1000).optional(),
  /** Shown with the review; first name only is asked for. */
  name: z.string().trim().max(40).optional(),
});

/** Public: the token is the permission. Each link takes one review. */
export async function submitReview(db: Firestore, input: unknown, now = new Date()): Promise<{ reviewId: string }> {
  const req = parseInput(submitReviewInput, input);
  const inviteRef = db.collection('reviewInvites').doc(req.token);
  const reviewRef = db.collection('reviews').doc();
  await db.runTransaction(async (tx) => {
    const invite = await tx.get(inviteRef);
    if (!invite.exists) throw new HttpsError('not-found', 'this review link is not valid');
    if (invite.get('usedAt')) throw new HttpsError('already-exists', 'a review was already left with this link');
    if ((invite.get('expiresAt').toDate() as Date) < now) throw new HttpsError('failed-precondition', 'this review link has expired');
    tx.create(reviewRef, {
      agentId: invite.get('agentId'),
      listingId: invite.get('listingId'),
      viewingId: invite.get('viewingId'),
      rating: req.rating,
      ...(req.comment ? { comment: req.comment } : {}),
      ...(req.name ? { name: req.name.split(/\s+/)[0] } : {}),
      status: 'pending',
      createdAt: now,
    });
    tx.update(inviteRef, { usedAt: now });
  });
  return { reviewId: reviewRef.id };
}

export const moderateReviewInput = z.object({ reviewId: docId, action: z.enum(['approve', 'hide']) });

/** Managers: approve shows a review; hide takes it down. The rating follows. */
export async function moderateReview(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ rating: number | null; ratingCount: number }> {
  requireManager(caller);
  const req = parseInput(moderateReviewInput, input);
  const ref = db.collection('reviews').doc(req.reviewId);
  const status = req.action === 'approve' ? 'approved' : 'hidden';
  let result = { rating: null as number | null, ratingCount: 0 };
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such review');
    const agentId = snap.get('agentId') as string;
    const approved = await tx.get(db.collection('reviews').where('agentId', '==', agentId).where('status', '==', 'approved').select('rating'));
    const ratings = approved.docs.filter((d) => d.id !== ref.id).map((d) => d.get('rating') as number);
    if (status === 'approved') ratings.push(snap.get('rating') as number);
    result = {
      rating: ratings.length ? Math.round((ratings.reduce((a, b) => a + b, 0) / ratings.length) * 10) / 10 : null,
      ratingCount: ratings.length,
    };
    tx.update(ref, { status, moderatedAt: now });
    tx.update(db.collection('agents').doc(agentId), { rating: result.rating, ratingCount: result.ratingCount });
    audit(tx, db, caller, {
      action: 'review.moderate',
      target: { collection: 'agents', id: agentId, label: `Review of ${agentId}, ${snap.get('rating')} stars` },
      from: snap.get('status'),
      to: status,
    }, now);
  });
  return result;
}

/** The agent's rating from their approved reviews, written back. */
export async function recomputeRating(db: Firestore, agentId: string): Promise<{ rating: number | null; ratingCount: number }> {
  const approved = await db.collection('reviews').where('agentId', '==', agentId).where('status', '==', 'approved').select('rating').get();
  const ratings = approved.docs.map((d) => d.get('rating') as number);
  const r = {
    rating: ratings.length ? Math.round((ratings.reduce((a, b) => a + b, 0) / ratings.length) * 10) / 10 : null,
    ratingCount: ratings.length,
  };
  await db.collection('agents').doc(agentId).update(r);
  return r;
}
