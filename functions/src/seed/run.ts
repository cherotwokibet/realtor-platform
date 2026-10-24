/**
 * Loads the demo seed into the Firestore EMULATOR, then checks it reads back.
 *   firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run seed"
 * Refuses to run without FIRESTORE_EMULATOR_HOST, so it can never touch a real project.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { collections } from '../model/schema';
import { seedDocs } from './data';

async function main(): Promise<void> {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('FIRESTORE_EMULATOR_HOST is not set: the seed only runs against the emulator.');
    process.exit(1);
  }
  initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? 'demo-realtor' });
  const db = getFirestore();
  const docs = seedDocs();
  for (const d of docs) collections[d.collection].parse(d.data);

  const batch = db.batch();
  for (const d of docs) batch.set(db.collection(d.collection).doc(d.id), d.data);
  await batch.commit();

  const expected = new Map<string, number>();
  for (const d of docs) expected.set(d.collection, (expected.get(d.collection) ?? 0) + 1);
  for (const [name, count] of expected) {
    const got = (await db.collection(name).count().get()).data().count;
    if (got !== count) throw new Error(`${name}: expected ${count} docs, emulator has ${got}`);
    console.log(`✓ ${name}: ${got}`);
  }
  // A geo query the app will run: listings in one area, cheapest first.
  const kilimani = await db.collection('listings').where('area', '==', 'kilimani').orderBy('priceKES').get();
  if (kilimani.empty) throw new Error('area query returned nothing');
  console.log(`✓ area query: ${kilimani.size} in kilimani`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
