/**
 * The starting area guides for a real project (P3-s05, go-live): the same
 * sixteen areas as the demo seed, with no demo figures. Their stats start
 * empty and the nightly areaStats job fills them from live listings; the
 * realtor rewrites guides and amenities in admin. Only missing areas are
 * created, so running it again never undoes an edit.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { geohash } from '../model/geo';
import { collections } from '../model/schema';
import { AREAS } from './data';

export function startingAreas(): { id: string; data: Record<string, unknown> }[] {
  return AREAS.map(({ slug, name, county, lat, lng, guide, amenities }) => {
    const data = { name, county, centre: { lat, lng, geohash: geohash(lat, lng) }, guide, amenities, stats: { medianRentKES: null, listings: 0 } };
    collections.areas.parse(data);
    return { id: slug, data };
  });
}

export async function loadAreas(db: Firestore): Promise<{ created: string[]; kept: string[] }> {
  const created: string[] = [];
  const kept: string[] = [];
  for (const a of startingAreas()) {
    const ref = db.collection('areas').doc(a.id);
    const made = await db.runTransaction(async (tx) => {
      if ((await tx.get(ref)).exists) return false;
      tx.create(ref, a.data);
      return true;
    });
    (made ? created : kept).push(a.id);
  }
  return { created, kept };
}

/** Which project to load: any of the tenant's, named in full; prod also needs CONFIRM=<project-id>. */
export function areasTarget(env: Record<string, string | undefined>): { projectId: string } | { error: string } {
  if (env.FIRESTORE_EMULATOR_HOST) return { projectId: env.GCLOUD_PROJECT ?? 'demo-realtor' };
  const p = env.PROJECT;
  if (!p || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(p)) return { error: 'Set PROJECT=<project-id> (for example the tenant\'s prod project).' };
  if (!/-(dev|stage)$/.test(p) && env.CONFIRM !== p) return { error: `${p} looks like a production project: run again with CONFIRM=${p}` };
  return { projectId: p };
}
