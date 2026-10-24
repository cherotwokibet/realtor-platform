import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { LowResolutionError, MIN_LONG_EDGE, processImage, VARIANTS } from './image';

/** A noisy 4000×3000 JPEG, like a 12 MP phone photo. */
async function phonePhoto(width = 4000, height = 3000, orientation?: number): Promise<Buffer> {
  const raw = Buffer.alloc(width * height * 3);
  for (let i = 0; i < raw.length; i++) raw[i] = (i * 2654435761) >>> 24;
  let img = sharp(raw, { raw: { width, height, channels: 3 } }).jpeg({ quality: 90 });
  if (orientation) img = img.withMetadata({ orientation });
  return img.toBuffer();
}

test('a 12 MP phone photo becomes three WebP variants and a blurhash, fast', async () => {
  const started = Date.now();
  const out = await processImage(await phonePhoto());
  const ms = Date.now() - started;
  assert.ok(ms < 30_000, `took ${ms} ms (budget 30 s)`);
  for (const [name, edge] of Object.entries(VARIANTS)) {
    const m = await sharp(out.variants[name as keyof typeof VARIANTS]).metadata();
    assert.equal(m.format, 'webp');
    assert.equal(Math.max(m.width!, m.height!), edge, name);
    assert.equal(m.exif, undefined, `${name} keeps no EXIF (GPS)`);
  }
  assert.deepEqual([out.width, out.height], [1600, 1200]);
  assert.match(out.blurhash, /^[0-9A-Za-z#$%*+,\-.:;=?@[\]^_{|}~]{20,}$/);
});

test('EXIF rotation is applied: a portrait shot stays portrait', async () => {
  const out = await processImage(await phonePhoto(4000, 3000, 6)); // 90° clockwise
  assert.deepEqual([out.width, out.height], [1200, 1600]);
});

test('low-resolution photos are rejected', async () => {
  await assert.rejects(processImage(await phonePhoto(MIN_LONG_EDGE - 1, 600)), LowResolutionError);
});

test('a watermark changes card and full but not thumb', async () => {
  const photo = await phonePhoto(2000, 1500);
  const mark = await sharp({ create: { width: 300, height: 160, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 1 } } }).png().toBuffer();
  const plain = await processImage(photo);
  const marked = await processImage(photo, { watermark: mark });
  assert.ok(plain.variants.thumb.equals(marked.variants.thumb));
  assert.ok(!plain.variants.card.equals(marked.variants.card));
});

test('a file that is not an image is refused', async () => {
  await assert.rejects(processImage(Buffer.from('not a photo')));
});
