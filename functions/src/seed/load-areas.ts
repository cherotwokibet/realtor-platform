/**
 * Loads the starting area guides into a real project, once (go-live step):
 *   PROJECT=<project-id> [CONFIRM=<project-id>] npm --prefix functions run areas:load
 * with Application Default Credentials. Areas already there are kept as they are.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { areasTarget, loadAreas } from './areas';

async function main(): Promise<void> {
  const target = areasTarget(process.env);
  if ('error' in target) {
    console.error(`✗ ${target.error}`);
    process.exit(1);
  }
  initializeApp({ projectId: target.projectId });
  const r = await loadAreas(getFirestore());
  console.log(`✓ ${target.projectId}: ${r.created.length} areas added${r.kept.length ? `, ${r.kept.length} already there and left as they are` : ''}`);
  console.log('  Area stats fill in overnight (areaStats); edit guides in the admin under Areas.');
}

main().catch((e) => {
  console.error(`✗ ${(e as Error).message}`);
  process.exit(1);
});
