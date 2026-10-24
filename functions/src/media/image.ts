/**
 * Photo normalisation (D6): one raw phone photo in, standard WebP variants,
 * a blurhash placeholder and size facts out. Pure: no Firebase here.
 */
import sharp from 'sharp';
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
  return { width: full.width!, height: full.height!, blurhash, variants };
}
