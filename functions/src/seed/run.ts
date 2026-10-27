/**
 * Loads the demo seed, then checks it reads back.
 *   Emulator: firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run seed"
 *   Dev project: SEED_PROJECT=<project-id-ending-in-dev> npm --prefix functions run seed   (Application Default Credentials)
 * Stage and prod are refused (see target.ts).
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { collections } from '../model/schema';
import { seedDocs } from './data';
import { seedTarget } from './target';

async function main(): Promise<void> {
  const target = seedTarget(process.env);
  if ('error' in target) {
    console.error(target.error);
    process.exit(1);
  }
  initializeApp({ projectId: target.projectId });
  console.log(`seeding ${target.emulator ? 'the emulator' : target.projectId} (${target.projectId})`);
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
    // A real dev project may hold more than the seed; the emulator holds exactly it.
    if (target.emulator ? got !== count : got < count) throw new Error(`${name}: expected ${count} docs, found ${got}`);
    console.log(`✓ ${name}: ${got}`);
  }
  // A query the app will run: listings in one area, cheapest first. On a
  // real project it needs the composite index, which takes minutes to build.
  try {
    const kilimani = await db.collection('listings').where('area', '==', 'kilimani').orderBy('priceKES').get();
    if (kilimani.empty) throw new Error('area query returned nothing');
    console.log(`✓ area query: ${kilimani.size} in kilimani`);
  } catch (e) {
    if (target.emulator || (e as { code?: number }).code !== 9) throw e;
    console.log('… area query: the (area, priceKES) index is still building; try again in a few minutes');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
