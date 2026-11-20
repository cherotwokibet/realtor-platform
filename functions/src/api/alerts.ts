import type { Firestore } from 'firebase-admin/firestore';
import type { Messaging } from 'firebase-admin/messaging';
import { insidePolygon } from '../model/geo';

/**
 * Saved-search alerts (D18, P4-s03). Every 5 minutes: the listings that went
 * live since the last sweep (`liveAt`), matched against every saved search;
 * each match becomes an alert in the owner's inbox (users/{uid}/alerts),
 * which the app shows. One alert per search and listing (the id says so).
 *
 * Push: phones that turned alerts on register under users/{uid}/devices
 * (the token is the id). Each sweep sends one notification per person, not
 * one per home, and forgets tokens FCM says are gone. Email reads the same
 * alerts once a sender is set up.
 */
export interface SearchFilters {
  purpose: string;
  types?: string[];
  areas?: string[];
  minBeds?: number;
  maxPriceKES?: number;
  /** A drawn area (P3-s04), as the search link writes it: 3 to 20 "lat,lng" joined by "~". */
  poly?: string;
}

export interface LiveRow {
  id: string;
  slug: string;
  title: string;
  purpose: string;
  type: string;
  area: string;
  beds: number;
  priceKES: number;
  lat?: number;
  lng?: number;
}

export { insidePolygon };

/** The corners of a saved drawn area, or null when it is not 3 to 20 real corners. */
export function parseArea(poly: string): Array<{ lat: number; lng: number }> | null {
  if (typeof poly !== 'string') return null;
  const corners = poly.split('~').map((c) => {
    const [lat, lng] = c.split(',').map(Number);
    return { lat, lng };
  });
  const ok =
    corners.length >= 3 &&
    corners.length <= 20 &&
    corners.every((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng) && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180);
  return ok ? corners : null;
}

/** No drawn area matches anywhere; a damaged one matches nothing. */
function inArea(f: SearchFilters, l: LiveRow): boolean {
  if (f.poly == null) return true;
  const corners = parseArea(f.poly);
  if (corners == null || l.lat == null || l.lng == null) return false;
  return insidePolygon(l.lat, l.lng, corners);
}

export function matches(f: SearchFilters, l: LiveRow): boolean {
  return (
    l.purpose === f.purpose &&
    (!f.types?.length || f.types.includes(l.type)) &&
    (!f.areas?.length || f.areas.includes(l.area)) &&
    (f.minBeds == null || l.beds >= f.minBeds) &&
    (f.maxPriceKES == null || l.priceKES <= f.maxPriceKES) &&
    inArea(f, l)
  );
}

/** At most this many alerts per search and sweep, so a bulk import can't flood an inbox. */
export const MAX_ALERTS_PER_SEARCH = 10;

/** One notification for one person; `path` is the app route a tap opens. */
export interface PushMessage {
  title: string;
  body: string;
  path: string;
}

export interface PushSender {
  /** Sends to every token; returns the tokens FCM says are no longer valid. */
  send(tokens: string[], m: PushMessage): Promise<string[]>;
}

/** FCM error codes that mean the app was removed or the token replaced. */
const GONE = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);

export function fcmSender(messaging: Messaging): PushSender {
  return {
    async send(tokens, m) {
      const gone: string[] = [];
      for (let i = 0; i < tokens.length; i += 500) {
        const batch = tokens.slice(i, i + 500);
        const r = await messaging.sendEachForMulticast({
          tokens: batch,
          notification: { title: m.title, body: m.body },
          data: { path: m.path },
          android: { priority: 'high', collapseKey: 'saved-search-alerts', notification: { tag: 'saved-search-alerts' } },
          apns: { payload: { aps: { 'thread-id': 'saved-search-alerts' } } },
        });
        r.responses.forEach((x, j) => {
          if (!x.success && GONE.has(x.error?.code ?? '')) gone.push(batch[j]);
        });
      }
      return gone;
    },
  };
}

const kes = (n: number) => `KES ${Math.round(n).toLocaleString('en-KE')}`;

/** What one person sees for this sweep's new homes. */
export function pushFor(hits: LiveRow[]): PushMessage {
  const first = hits[0];
  const price = `${kes(first.priceKES)}${first.purpose === 'rent' ? ' a month' : ''}`;
  if (hits.length === 1) return { title: 'A new home matches your search', body: `${first.title}, ${price}`, path: `/listing/${first.slug}` };
  return { title: `${hits.length} new homes match your searches`, body: `${first.title}, ${price}, and ${hits.length - 1} more`, path: '/account' };
}

/** At most this many phones per person get a push. */
export const MAX_DEVICES = 10;

export async function sweepSavedSearches(
  db: Firestore,
  now = new Date(),
  push?: PushSender,
): Promise<{ listings: number; alerts: number; pushed: number }> {
  const stateRef = db.collection('config').doc('alerts');
  const since = ((await stateRef.get()).get('lastSweepAt')?.toDate() as Date | undefined) ?? new Date(now.getTime() - 3_600_000);
  const fresh = await db.collection('listings').where('status', '==', 'live').where('liveAt', '>', since).where('liveAt', '<=', now).get();
  let alerts = 0;
  let pushed = 0;
  if (!fresh.empty) {
    const rows: LiveRow[] = fresh.docs.map((d) => ({
      id: d.id,
      slug: d.get('slug'),
      title: d.get('title'),
      purpose: d.get('purpose'),
      type: d.get('type'),
      area: d.get('area'),
      beds: d.get('beds'),
      priceKES: d.get('priceKES'),
      lat: d.get('geo.lat'),
      lng: d.get('geo.lng'),
    }));
    const writer = db.bulkWriter();
    const searches = await db.collection('savedSearches').where('channels', 'array-contains', 'inbox').get();
    const perUser = new Map<string, Map<string, LiveRow>>();
    for (const s of searches.docs) {
      const hits = rows.filter((r) => matches(s.get('filters') as SearchFilters, r)).slice(0, MAX_ALERTS_PER_SEARCH);
      const mine = perUser.get(s.get('userId')) ?? new Map<string, LiveRow>();
      for (const r of hits) mine.set(r.id, r);
      if (hits.length) perUser.set(s.get('userId'), mine);
      for (const r of hits) {
        const ref = db.collection('users').doc(s.get('userId')).collection('alerts').doc(`${s.id}_${r.id}`);
        void writer.set(ref, { searchId: s.id, listingId: r.id, slug: r.slug, title: r.title, priceKES: r.priceKES, purpose: r.purpose, area: r.area, createdAt: now, readAt: null });
        alerts++;
      }
      if (hits.length) void writer.update(s.ref, { lastNotifiedAt: now });
    }
    await writer.close();
    if (push) pushed = await sendPushes(db, perUser, push);
  }
  await stateRef.set({ lastSweepAt: now }, { merge: true });
  return { listings: fresh.size, alerts, pushed };
}

/** One push per person with a registered phone. A failed send never stops the sweep: the inbox already has the alerts. */
async function sendPushes(db: Firestore, perUser: Map<string, Map<string, LiveRow>>, push: PushSender): Promise<number> {
  let sent = 0;
  for (const [uid, homes] of perUser) {
    try {
      const devices = await db.collection('users').doc(uid).collection('devices').orderBy('updatedAt', 'desc').limit(MAX_DEVICES).get();
      if (devices.empty) continue;
      const tokens = devices.docs.map((d) => d.get('token') as string).filter((t) => typeof t === 'string' && t.length > 0);
      const gone = await push.send(tokens, pushFor([...homes.values()]));
      await Promise.all(devices.docs.filter((d) => gone.includes(d.get('token'))).map((d) => d.ref.delete()));
      sent += tokens.length - gone.length;
    } catch (e) {
      console.error(`push to ${uid}: ${e instanceof Error ? e.message : e}`);
    }
  }
  return sent;
}
