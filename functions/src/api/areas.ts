import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { geohash, insidePolygon, selfIntersects, slugify } from '../model/geo';
import { boundary, slug } from '../model/schema';
import { audit } from './audit';
import { median } from './response';
import { type Caller, parseInput, requireManager } from './auth';

/**
 * Area guides (P3-s05): managers write each neighbourhood's guide and
 * nearby amenities; the share pages show them at /area/<slug> and the
 * listing form offers the areas. stats (median rent, live listings) are
 * not sent here: refreshAreaStats recomputes them every night.
 */
export const saveAreaInput = z.object({
  /** Existing area; a new one's slug comes from the name. */
  slug: slug.optional(),
  name: z.string().trim().min(2).max(60),
  county: z.string().trim().min(2).max(40),
  lat: z.number().min(-5).max(5),
  lng: z.number().min(33).max(42),
  guide: z.string().trim().max(5000),
  amenities: z.array(z.string().trim().min(1).max(60)).max(30),
  /** The area's outline (geofence); null or absent: none yet. */
  boundary: boundary.nullable().optional(),
});

export async function saveArea(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ slug: string }> {
  requireManager(caller);
  const req = parseInput(saveAreaInput, input);
  if (req.boundary) {
    if (selfIntersects(req.boundary)) throw new HttpsError('invalid-argument', 'boundary: its edges cross');
    if (!insidePolygon(req.lat, req.lng, req.boundary)) throw new HttpsError('invalid-argument', 'boundary: the centre must be inside it');
  }
  const id = req.slug ?? slugify(req.name);
  if (!id) throw new HttpsError('invalid-argument', 'name: needs letters or numbers');
  const ref = db.collection('areas').doc(id);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (req.slug && !snap.exists) throw new HttpsError('not-found', `no area "${req.slug}"`);
    if (!req.slug && snap.exists) throw new HttpsError('already-exists', `there is already an area "${id}"`);
    const fields = {
      name: req.name,
      county: req.county,
      centre: { lat: req.lat, lng: req.lng, geohash: geohash(req.lat, req.lng) },
      guide: req.guide,
      amenities: req.amenities,
      ...(req.boundary !== undefined ? { boundary: req.boundary } : {}),
      updatedAt: now,
    };
    if (snap.exists) tx.update(ref, fields);
    else tx.create(ref, { ...fields, stats: { medianRentKES: null, listings: 0 } });
    audit(tx, db, caller, { action: 'area.save', target: { collection: 'areas', id, label: req.name }, from: snap.exists ? 'saved' : 'none', to: 'saved' }, now);
  });
  return { slug: id };
}

/**
 * Nightly: each area's live listings and the median monthly rent of its
 * live rentals (null with fewer than MIN_RENTALS, too few to mean much).
 */
export const MIN_RENTALS = 3;

export async function refreshAreaStats(db: Firestore): Promise<{ areas: number }> {
  const [areas, live] = await Promise.all([
    db.collection('areas').select().get(),
    db.collection('listings').where('status', '==', 'live').select('area', 'purpose', 'priceKES').get(),
  ]);
  const rents = new Map<string, number[]>(), counts = new Map<string, number>();
  for (const l of live.docs) {
    const a = l.get('area') as string;
    counts.set(a, (counts.get(a) ?? 0) + 1);
    if (l.get('purpose') === 'rent') rents.set(a, [...(rents.get(a) ?? []), l.get('priceKES') as number]);
  }
  const writer = db.bulkWriter();
  for (const a of areas.docs) {
    const r = rents.get(a.id) ?? [];
    void writer.update(a.ref, { stats: { medianRentKES: r.length >= MIN_RENTALS ? median(r) : null, listings: counts.get(a.id) ?? 0 } });
  }
  await writer.close();
  return { areas: areas.size };
}
