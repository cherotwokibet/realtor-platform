/**
 * Storage trigger body: uploads/{agents/<agentId>|staff/<uid>}/listings/{listingId}/{file}
 * -> variants under media/listings/{listingId}/{mediaId}/, a media entry on
 * the listing, and the raw upload deleted. storage.rules lets an agent write
 * only under their own agentId; here we check the listing is theirs.
 * Retries are safe: mediaId is a content hash.
 */
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Bucket } from '@google-cloud/storage';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { LowResolutionError, processImage, VARIANTS } from './image';
import { processVideo, VideoRejectedError } from './video';

export const UPLOAD_PATH = /^uploads\/(agents|staff)\/([A-Za-z0-9_-]{1,128})\/listings\/([A-Za-z0-9_-]{1,128})\/[^/]+$/;
/** The tenant's mark, uploaded by the deploy step. Optional. */
export const WATERMARK_PATH = 'brand/watermark.png';

export type UploadResult =
  | { status: 'ignored' }
  | { status: 'rejected'; reason: string }
  | { status: 'processed'; mediaId: string; variants: Record<string, string> };

export async function handleListingUpload(bucket: Bucket, db: Firestore, path: string, now = new Date()): Promise<UploadResult> {
  const m = UPLOAD_PATH.exec(path);
  if (!m || VIDEO_EXT.test(path)) return { status: 'ignored' };
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

    const entry = { kind: 'photo', variants, blurhash: out.blurhash, width: out.width, height: out.height };
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(listingRef);
      if (!snap.exists) return; // listing deleted meanwhile: variants stay orphaned for the cleanup job
      const media = (snap.get('media') ?? []) as { variants?: Record<string, string> }[];
      if (media.some((x) => x.variants?.full === variants.full)) return; // retry
      tx.update(listingRef, { media: FieldValue.arrayUnion(entry), lastMediaError: FieldValue.delete(), updatedAt: now });
    });
    return { status: 'processed', mediaId, variants };
  } finally {
    await raw.delete({ ignoreNotFound: true });
  }
}

export const VIDEO_EXT = /\.(mp4|mov|m4v|3gp)$/i;

/**
 * Same upload paths as photos; a video becomes an HLS ladder under
 * media/listings/{listingId}/{mediaId}/hls/ plus a poster, and a
 * `{kind:'video'}` media entry. The raw upload is always deleted.
 */
export async function handleListingVideo(bucket: Bucket, db: Firestore, path: string, now = new Date()): Promise<UploadResult> {
  const m = UPLOAD_PATH.exec(path);
  if (!m || !VIDEO_EXT.test(path)) return { status: 'ignored' };
  const [, kind, uploader, listingId] = m;
  const raw = bucket.file(path);
  const listingRef = db.collection('listings').doc(listingId);
  const work = await mkdtemp(join(tmpdir(), 'video-'));

  try {
    const listing = await listingRef.get();
    if (!listing.exists) return { status: 'rejected', reason: 'no such listing' };
    if (kind === 'agents' && listing.get('agentId') !== uploader) return { status: 'rejected', reason: 'not this agent\'s listing' };
    const src = join(work, 'in');
    await raw.download({ destination: src });
    const mediaId = createHash('sha256').update(await readFile(src)).digest('hex').slice(0, 16);

    let out;
    try {
      out = await processVideo(src, join(work, 'hls'));
    } catch (e) {
      const reason = e instanceof VideoRejectedError ? e.message : 'not a readable video';
      await listingRef.update({ lastMediaError: { file: path.split('/').pop(), reason, at: now } });
      return { status: 'rejected', reason };
    }

    const base = `media/listings/${listingId}/${mediaId}`;
    for (const f of out.files) {
      const poster = f === 'poster.jpg';
      await bucket.upload(join(work, 'hls', f), {
        destination: poster ? `${base}/poster.jpg` : `${base}/hls/${f}`,
        contentType: f.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : f.endsWith('.ts') ? 'video/mp2t' : 'image/jpeg',
        metadata: { cacheControl: f.endsWith('.m3u8') ? 'public, max-age=60' : 'public, max-age=31536000, immutable' },
        resumable: false,
      });
    }

    const variants = { hls: `${base}/hls/master.m3u8`, poster: `${base}/poster.jpg` };
    const entry = { kind: 'video', variants, width: out.info.width, height: out.info.height, durationSec: Math.round(out.info.durationSec) };
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(listingRef);
      if (!snap.exists) return;
      const media = (snap.get('media') ?? []) as { variants?: Record<string, string> }[];
      if (media.some((x) => x.variants?.hls === variants.hls)) return; // retry
      tx.update(listingRef, { media: FieldValue.arrayUnion(entry), lastMediaError: FieldValue.delete(), updatedAt: now });
    });
    return { status: 'processed', mediaId, variants };
  } finally {
    await raw.delete({ ignoreNotFound: true });
    await rm(work, { recursive: true, force: true });
  }
}
