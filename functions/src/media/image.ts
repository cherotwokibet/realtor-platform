/**
 * Photo normalisation (D6): one raw phone photo in, standard WebP variants,
 * a blurhash placeholder and size facts out. Pure: no Firebase here.
 */
import sharp, { type Sharp } from 'sharp';
import { encode } from 'blurhash';

/** Longest edge per variant, in pixels. */
export const VARIANTS = { thumb: 320, card: 800, full: 1600 } as const;
export type VariantName = keyof typeof VARIANTS;

/** Photos smaller than this on the long edge are rejected (blurry on listing pages). */
export const MIN_LONG_EDGE = 1024;

export class LowResolutionError extends Error {}

export interface ProcessedImage {
  width: number;
  height: number;
  blurhash: string;
  /** dHash of the photo before any watermark (see [dHash]). */
  phash: string;
  variants: Record<VariantName, Buffer>;
}

export async function processImage(input: Buffer, opts: { watermark?: Buffer } = {}): Promise<ProcessedImage> {
  // rotate() applies the EXIF orientation; metadata (GPS, camera) is dropped by default.
  const base = sharp(input, { failOn: 'error' }).rotate();
  const meta = await base.clone().metadata();
  const [w0, h0] = (meta.orientation ?? 1) >= 5 ? [meta.height!, meta.width!] : [meta.width!, meta.height!];
  if (Math.max(w0, h0) < MIN_LONG_EDGE) {
    throw new LowResolutionError(`photo is ${w0}×${h0}; the long edge must be at least ${MIN_LONG_EDGE}px`);
  }

  const variants = {} as Record<VariantName, Buffer>;
  for (const [name, edge] of Object.entries(VARIANTS) as [VariantName, number][]) {
    let img = base.clone().resize({ width: edge, height: edge, fit: 'inside', withoutEnlargement: true });
    if (opts.watermark && name !== 'thumb') {
      const resized = await img.toBuffer({ resolveWithObject: true });
      const markWidth = Math.round(resized.info.width * 0.18);
      const mark = await sharp(opts.watermark).resize({ width: markWidth }).ensureAlpha(0.7).toBuffer();
      img = sharp(resized.data).composite([{ input: mark, gravity: 'southeast', blend: 'over' }]);
    }
    variants[name] = await img.webp({ quality: name === 'thumb' ? 70 : 80 }).toBuffer();
  }

  const small = await base.clone().resize(32, 32, { fit: 'inside' }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const blurhash = encode(new Uint8ClampedArray(small.data), small.info.width, small.info.height, 4, 3);

  const full = await sharp(variants.full).metadata();
  return { width: full.width!, height: full.height!, blurhash, phash: await dHash(base), variants };
}

/**
 * 64-bit difference hash as 16 hex digits: each bit says whether a pixel of
 * a 9×8 greyscale thumbnail is brighter than its right-hand neighbour. It
 * survives resizing, re-encoding, a watermark and small crops, so the same
 * photo posted twice lands within a few bits.
 */
export async function dHash(img: Sharp): Promise<string> {
  const { data } = await img.clone().greyscale().resize(9, 8, { fit: 'fill' }).raw().toBuffer({ resolveWithObject: true });
  let bits = 0n;
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) bits = (bits << 1n) | (data[y * 9 + x] > data[y * 9 + x + 1] ? 1n : 0n);
  }
  return bits.toString(16).padStart(16, '0');
}

/** How many of the 64 bits differ between two hashes. */
export function hammingDistance(a: string, b: string): number {
  let x = BigInt(`0x${a}`) ^ BigInt(`0x${b}`);
  let n = 0;
  for (; x; x >>= 1n) n += Number(x & 1n);
  return n;
}
