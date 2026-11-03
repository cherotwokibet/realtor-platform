/**
 * Starting areas against the Firestore emulator:
 *   firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run test:emulator"
 */
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { loadAreas } from './areas';

let db: Firestore;
const saved = new Map<string, DocumentData | undefined>();

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run inside firebase emulators:exec');
  if (!getApps().length) initializeApp({ projectId: 'demo-realtor' });
  db = getFirestore();
  for (const id of ['kilimani', 'westlands']) saved.set(id, (await db.collection('areas').doc(id).get()).data());
});

after(async () => {
  for (const [id, data] of saved) {
    if (data) await db.collection('areas').doc(id).set(data);
    else await db.collection('areas').doc(id).delete();
  }
});

test('adds missing areas and leaves edited ones alone; a second run adds nothing', async () => {
  await db.collection('areas').doc('kilimani').delete();
  await db.collection('areas').doc('westlands').set({ ...(saved.get('westlands') ?? {}), name: 'Westlands', guide: 'Edited by the realtor' });
  const r = await loadAreas(db);
  assert.ok(r.created.includes('kilimani'));
  assert.ok(r.kept.includes('westlands'));
  const k = (await db.collection('areas').doc('kilimani').get()).data()!;
  assert.deepEqual(k.stats, { medianRentKES: null, listings: 0 });
  assert.equal((await db.collection('areas').doc('westlands').get()).get('guide'), 'Edited by the realtor');
  assert.equal((await loadAreas(db)).created.length, 0);
});
