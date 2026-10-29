import type { Firestore } from 'firebase-admin/firestore';
import { z } from 'zod';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';

/**
 * Site pages (P5-s07): About, Privacy, Terms, FAQ and Contact, written by
 * managers in the admin and shown by the share pages at /<slug> as soon as
 * they are published, with no redeploy. Plain text: "# " starts a heading,
 * "- " a list item, a blank line a new paragraph.
 */
export const PAGE_SLUGS = ['about', 'privacy', 'terms', 'faq', 'contact'] as const;

export const savePageInput = z.object({
  slug: z.enum(PAGE_SLUGS),
  title: z.string().trim().min(2).max(80),
  body: z.string().max(20_000),
  published: z.boolean(),
});

export async function savePage(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ slug: string }> {
  requireManager(caller);
  const req = parseInput(savePageInput, input);
  const ref = db.collection('pages').doc(req.slug);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    tx.set(ref, { title: req.title, body: req.body, published: req.published, updatedAt: now, updatedBy: caller.uid });
    audit(tx, db, caller, {
      action: 'page.save',
      target: { collection: 'pages', id: req.slug, label: req.title },
      from: snap.exists ? (snap.get('published') ? 'published' : 'draft') : 'none',
      to: req.published ? 'published' : 'draft',
    }, now);
  });
  return { slug: req.slug };
}
