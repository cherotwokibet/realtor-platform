/**
 * Storage trigger body: uploads/{agents/<agentId>|staff/<uid>}/listings/{listingId}/{file}
 * -> variants under media/listings/{listingId}/{mediaId}/, a media entry on
 * the listing, and the raw upload deleted. storage.rules lets an agent write
 * only under their own agentId; here we check the listing is theirs.
 * Retries are safe: mediaId is a content hash.
 */
import { createHash } from 'node:crypto';
import type { Bucket } from '@google-cloud/storage';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { LowResolutionError, processImage, VARIANTS } from './image';
import { findDuplicates, type PhotoMatch } from './duplicates';

export const UPLOAD_PATH = /^uploads\/(agents|staff)\/([A-Za-z0-9_-]{1,128})\/listings\/([A-Za-z0-9_-]{1,128})\/[^/]+$/;
/** The tenant's mark, uploaded by the deploy step. Optional. */
export const WATERMARK_PATH = 'brand/watermark.png';

export type UploadResult =
  | { status: 'ignored' }
  | { status: 'rejected'; reason: string }
  | { status: 'processed'; mediaId: string; variants: Record<string, string>; duplicates: PhotoMatch[] };

export async function handleListingUpload(bucket: Bucket, db: Firestore, path: string, now = new Date()): Promise<UploadResult> {
  const m = UPLOAD_PATH.exec(path);
  if (!m) return { status: 'ignored' };
  const [, kind, uploader, listingId] = m;
  const raw = bucket.file(path);
  const listingRef = db.collection('listings').doc(listingId);

  try {
    const listing = await listingRef.get();
    if (!listing.exists) return { status: 'rejected', reason: 'no such listing' };
    if (kind === 'agents' && listing.get('agentId') !== uploader) return { status: 'rejected', reason: 'not this agent\'s listing' };
    const [input] = await raw.download();
    const mediaId = createHash('sha256').update(input).digest('hex').slice(0, 16);
    const [hasMark] = await bucket.file(WATERMARK_PATH).exists();
    const watermark = hasMark ? (await bucket.file(WATERMARK_PATH).download())[0] : undefined;

    let out;
    try {
      out = await processImage(input, { watermark });
    } catch (e) {
      const reason = e instanceof LowResolutionError ? e.message : 'not a readable image';
      await listingRef.update({ lastMediaError: { file: path.split('/').pop(), reason, at: now } });
      return { status: 'rejected', reason };
    }

    const variants: Record<string, string> = {};
    for (const name of Object.keys(VARIANTS) as (keyof typeof VARIANTS)[]) {
      const dest = `media/listings/${listingId}/${mediaId}/${name}.webp`;
      await bucket.file(dest).save(out.variants[name], {
        contentType: 'image/webp',
        metadata: { cacheControl: 'public, max-age=31536000, immutable' },
        resumable: false,
      });
      variants[name] = dest;
    }

    const entry = { kind: 'photo', variants, blurhash: out.blurhash, width: out.width, height: out.height, phash: out.phash };
    let duplicates: PhotoMatch[] = [];
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(listingRef);
      if (!snap.exists) return; // listing deleted meanwhile: variants stay orphaned for the cleanup job
      const dupes = await findDuplicates(tx, db, { hash: out.phash, listingId, mediaId }, now);
      duplicates = dupes.matches;
      const media = (snap.get('media') ?? []) as { variants?: Record<string, string> }[];
      if (media.some((x) => x.variants?.full === variants.full)) return; // retry
      dupes.write();
      tx.update(listingRef, { media: FieldValue.arrayUnion(entry), lastMediaError: FieldValue.delete(), updatedAt: now });
    });
    if (duplicates.length) console.warn(`listing ${listingId}: photo ${mediaId} matches ${duplicates.map((d) => d.listingId).join(', ')}`);
    return { status: 'processed', mediaId, variants, duplicates };
  } finally {
    await raw.delete({ ignoreNotFound: true });
  }
}
