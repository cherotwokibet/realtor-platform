/**
 * Adverts managers run on the site: on the home page's band and among the
 * results. Each has its words, an optional photo (uploaded by the admin to
 * ads/<id>/ in Storage), where a tap goes (a link, or the realtor's WhatsApp
 * when there is none), where it shows, and when (on or off, and optional
 * start and end days). The site reads the ones switched on and picks those
 * in date.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId } from '../model/schema';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';

export const AD_PLACEMENTS = ['home', 'results', 'both'] as const;

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'a day, YYYY-MM-DD');

export const saveAdInput = z
  .object({
    adId: docId.optional(),
    title: z.string().trim().min(2).max(80),
    text: z.string().trim().max(200).default(''),
    advertiser: z.string().trim().max(80).default(''),
    /** https only; empty: Enquire now opens the realtor's WhatsApp. */
    linkUrl: z.url({ protocol: /^https$/ }).max(500).optional(),
    /** A Storage path under ads/<adId>/. */
    image: z.string().regex(/^ads\/[A-Za-z0-9_-]+\/[A-Za-z0-9._-]+$/).max(200).optional(),
    placement: z.enum(AD_PLACEMENTS),
    active: z.boolean(),
    startsOn: day.optional(),
    endsOn: day.optional(),
  })
  .refine((a) => !a.startsOn || !a.endsOn || a.startsOn <= a.endsOn, { message: 'ends before it starts', path: ['endsOn'] })
  .refine((a) => !a.adId || !a.image || a.image.startsWith(`ads/${a.adId}/`), { message: "image: this ad's own photo", path: ['image'] });

export async function saveAd(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ adId: string }> {
  requireManager(caller);
  const req = parseInput(saveAdInput, input);
  const ref = req.adId ? db.collection('ads').doc(req.adId) : db.collection('ads').doc();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (req.adId && !snap.exists) throw new HttpsError('not-found', 'no such ad');
    const { adId: _id, ...fields } = req;
    tx.set(ref, {
      ...fields,
      linkUrl: fields.linkUrl ?? null,
      image: fields.image ?? null,
      startsOn: fields.startsOn ?? null,
      endsOn: fields.endsOn ?? null,
      createdAt: snap.exists ? snap.get('createdAt') : now,
      updatedAt: now,
    });
    audit(tx, db, caller, {
      action: 'ad.save',
      target: { collection: 'ads', id: ref.id, label: req.title },
      from: snap.exists ? (snap.get('active') ? 'on' : 'off') : 'none',
      to: req.active ? 'on' : 'off',
    }, now);
  });
  return { adId: ref.id };
}

export const deleteAdInput = z.object({ adId: docId });

export async function deleteAd(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ deleted: true }> {
  requireManager(caller);
  const req = parseInput(deleteAdInput, input);
  const ref = db.collection('ads').doc(req.adId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such ad');
    tx.delete(ref);
    audit(tx, db, caller, { action: 'ad.delete', target: { collection: 'ads', id: ref.id, label: snap.get('title') as string }, from: 'saved', to: 'none' }, now);
  });
  return { deleted: true };
}
