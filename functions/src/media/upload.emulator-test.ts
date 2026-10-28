/**
 * Upload trigger body against the Firestore + Storage emulators:
 *   firebase emulators:exec --only firestore,storage --project demo-realtor "npm --prefix functions run test:emulator"
 */
import { before, test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import type { Bucket } from '@google-cloud/storage';
import { seedDocs } from '../seed/data';
import { handleListingUpload } from './upload';

let db: Firestore;
let bucket: Bucket;

before(async () => {
  assert.ok(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 'run with --only firestore,storage');
  if (!getApps().length) initializeApp({ projectId: 'demo-realtor', storageBucket: 'demo-realtor.appspot.com' });
  db = getFirestore();
  bucket = getStorage().bucket('demo-realtor.appspot.com');
  for (const id of ['listing-001', 'listing-002']) {
    await db.collection('listings').doc(id).set(seedDocs().find((d) => d.id === id)!.data);
  }
});

const photo = (w: number, h: number) =>
  sharp({ create: { width: w, height: h, channels: 3, background: { r: 120, g: 80, b: 40 } } }).jpeg().toBuffer();

test('an upload becomes variants and a media entry; the raw file is removed', async () => {
  const path = 'uploads/agents/agent-wanjiku/listings/listing-001/IMG_0001.jpg';
  await bucket.file(path).save(await photo(4000, 3000), { contentType: 'image/jpeg' });
  const r = await handleListingUpload(bucket, db, path);
  assert.equal(r.status, 'processed');
  if (r.status !== 'processed') return;
  for (const p of Object.values(r.variants)) assert.ok((await bucket.file(p).exists())[0], p);
  assert.equal((await bucket.file(path).exists())[0], false);
  const media = (await db.collection('listings').doc('listing-001').get()).get('media');
  assert.equal(media.length, 1);
  assert.equal(media[0].width, 1600);

  // Same photo again (a retry): no duplicate entry.
  await bucket.file(path).save(await photo(4000, 3000), { contentType: 'image/jpeg' });
  await handleListingUpload(bucket, db, path);
  assert.equal((await db.collection('listings').doc('listing-001').get()).get('media').length, 1);
});

test('a small photo is rejected and recorded on the listing', async () => {
  const path = 'uploads/agents/agent-wanjiku/listings/listing-001/tiny.jpg';
  await bucket.file(path).save(await photo(640, 480), { contentType: 'image/jpeg' });
  const r = await handleListingUpload(bucket, db, path);
  assert.equal(r.status, 'rejected');
  const err = (await db.collection('listings').doc('listing-001').get()).get('lastMediaError');
  assert.match(err.reason, /at least 1024px/);
  assert.equal((await bucket.file(path).exists())[0], false);
});

test("an agent's upload to someone else's listing is rejected and deleted", async () => {
  const path = 'uploads/agents/agent-otieno/listings/listing-001/sneaky.jpg';
  await bucket.file(path).save(await photo(4000, 3000), { contentType: 'image/jpeg' });
  const r = await handleListingUpload(bucket, db, path);
  assert.deepEqual(r, { status: 'rejected', reason: "not this agent's listing" });
  assert.equal((await bucket.file(path).exists())[0], false);
});

test('paths outside uploads/ are ignored', async () => {
  assert.deepEqual(await handleListingUpload({} as Bucket, {} as Firestore, 'brand/watermark.png'), { status: 'ignored' });
});

/** A photo-like picture (soft shapes from [seed]) at 1600×1200. */
async function scene(seed: number): Promise<Buffer> {
  const [width, height] = [1600, 1200];
  const raw = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const v = 128 + 60 * Math.sin((x / width) * (3 + seed) + seed) + 50 * Math.cos((y / height) * (2 + seed * 1.7) - seed);
      const i = (y * width + x) * 3;
      raw[i] = raw[i + 1] = raw[i + 2] = Math.max(0, Math.min(255, v));
    }
  }
  return sharp(raw, { raw: { width, height, channels: 3 } }).jpeg({ quality: 90 }).toBuffer();
}

test("the same photo on another agent's listing is flagged for managers; plain photos are not", async () => {
  const otieno = (await db.collection('listings').doc('listing-002').get()).get('agentId');
  const first = 'uploads/agents/agent-wanjiku/listings/listing-001/lounge.jpg';
  await bucket.file(first).save(await scene(1), { contentType: 'image/jpeg' });
  const a = await handleListingUpload(bucket, db, first);
  assert.equal(a.status, 'processed');
  if (a.status !== 'processed') return;
  assert.deepEqual(a.duplicates, []);

  // Someone takes it, re-saves it smaller and posts it on their listing.
  const copy = `uploads/agents/${otieno}/listings/listing-002/my-lounge.jpg`;
  await bucket.file(copy).save(await sharp(await scene(1)).resize(1280).jpeg({ quality: 60 }).toBuffer(), { contentType: 'image/jpeg' });
  const b = await handleListingUpload(bucket, db, copy);
  if (b.status !== 'processed') return assert.fail(JSON.stringify(b));
  assert.equal(b.duplicates.length, 1);
  assert.equal(b.duplicates[0].listingId, 'listing-001');
  assert.equal(b.duplicates[0].mediaId, a.mediaId);
  const flag = (await db.collection('photoFlags').doc(`listing-002_${b.mediaId}`).get()).data()!;
  assert.equal(flag.matches[0].listingId, 'listing-001');
  const media = (await db.collection('listings').doc('listing-002').get()).get('media');
  assert.match(media.at(-1).phash, /^[0-9a-f]{16}$/);

  // A different photo, and a plain one, raise nothing.
  const other = `uploads/agents/${otieno}/listings/listing-002/kitchen.jpg`;
  await bucket.file(other).save(await scene(4), { contentType: 'image/jpeg' });
  const c = await handleListingUpload(bucket, db, other);
  assert.deepEqual(c.status === 'processed' && c.duplicates, []);
  const plain = `uploads/agents/${otieno}/listings/listing-002/wall.jpg`;
  await bucket.file(plain).save(await photo(4000, 3000), { contentType: 'image/jpeg' });
  const d = await handleListingUpload(bucket, db, plain);
  assert.deepEqual(d.status === 'processed' && d.duplicates, []);
});

