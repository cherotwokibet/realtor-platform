import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { slugify } from '../model/geo';
import { paymentStage, projectUnit, slug } from '../model/schema';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';
import { tenantFeatures } from './features';

/**
 * Off-plan projects (P5-s06): a development sold before it is finished.
 * Managers write each project's units (from-prices in KES), payment plan and
 * expected completion; the share pages show published ones at
 * /project/<slug> and list them at /projects, only for tenants with the
 * `offPlan` switch on. Progress photos come with the media pipeline later.
 */
export const saveProjectInput = z
  .object({
    /** Existing project; a new one's slug comes from the name. */
    slug: slug.optional(),
    name: z.string().trim().min(3).max(80),
    developer: z.string().trim().min(2).max(80),
    area: slug,
    summary: z.string().trim().max(5000),
    /** Expected handover, `YYYY-MM`. */
    completion: z.string().regex(/^20\d\d-(0[1-9]|1[0-2])$/, 'YYYY-MM'),
    units: z.array(projectUnit).min(1).max(20),
    /** Stages in order, e.g. deposit 10%, on signing 20%, …; percents total 100. */
    paymentPlan: z.array(paymentStage).min(1).max(12),
    published: z.boolean(),
  })
  .refine((p) => p.paymentPlan.reduce((sum, s) => sum + s.percent, 0) === 100, { message: 'paymentPlan: the stages must add up to 100%', path: ['paymentPlan'] });

export async function saveProject(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ slug: string }> {
  requireManager(caller);
  const req = parseInput(saveProjectInput, input);
  const features = await tenantFeatures(db);
  if (features?.offPlan === false) throw new HttpsError('failed-precondition', 'off-plan projects are switched off for this site');
  const id = req.slug ?? slugify(req.name);
  if (!id) throw new HttpsError('invalid-argument', 'name: needs letters or numbers');
  const ref = db.collection('projects').doc(id);
  await db.runTransaction(async (tx) => {
    const [snap, area] = await Promise.all([tx.get(ref), tx.get(db.collection('areas').doc(req.area))]);
    if (req.slug && !snap.exists) throw new HttpsError('not-found', `no project "${req.slug}"`);
    if (!req.slug && snap.exists) throw new HttpsError('already-exists', `there is already a project "${id}"`);
    if (!area.exists) throw new HttpsError('invalid-argument', `area: no area "${req.area}"`);
    const { slug: _, ...fields } = req;
    tx.set(ref, { ...fields, fromKES: Math.min(...req.units.map((u) => u.fromKES)), updatedAt: now, updatedBy: caller.uid });
    audit(tx, db, caller, {
      action: 'project.save',
      target: { collection: 'projects', id, label: req.name },
      from: snap.exists ? (snap.get('published') ? 'published' : 'draft') : 'none',
      to: req.published ? 'published' : 'draft',
    }, now);
  });
  return { slug: id };
}
