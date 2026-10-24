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
  const l = seedDocs().find((d) => d.id === 'listing-001')!;
  await db.collection('listings').doc('listing-001').set(l.data);
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
