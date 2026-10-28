/**
 * Duplicate and stolen photos (P6-s05). Every photo's dHash goes into an
 * index of 8 bands of 8 bits (`photoHashes/{band}_{2 hex}`). Two hashes
 * within 7 bits of each other share at least one band, so looking up a new
 * photo reads 8 small documents, never the whole collection. A match on
 * another listing is flagged for managers (`photoFlags/{listingId}_{mediaId}`);
 * nothing is blocked, because one building's photo can honestly serve two
 * units, and a person decides.
 */
import { FieldValue, type DocumentReference, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { hammingDistance } from './image';

/** At most this many differing bits counts as the same photo. */
export const SAME_PHOTO_BITS = 6;
const BANDS = 8;

interface Entry {
  h: string; // hash
  l: string; // listingId
  m: string; // mediaId
}

export interface PhotoMatch {
  listingId: string;
  mediaId: string;
  bits: number;
}

/**
 * A near-flat picture (a bare wall, a solid colour) hashes to almost all
 * zeros or ones, so it would "match" every other plain photo: such hashes
 * are neither indexed nor compared.
 */
export function tooPlain(hash: string): boolean {
  const ones = hammingDistance(hash, '0000000000000000');
  return ones < 6 || ones > 58;
}

const bandRefs = (db: Firestore, hash: string): DocumentReference[] =>
  Array.from({ length: BANDS }, (_, i) => db.collection('photoHashes').doc(`${i}_${hash.slice(i * 2, i * 2 + 2)}`));

/**
 * Reads the index in [tx] and returns the other listings' photos within
 * SAME_PHOTO_BITS, nearest first, plus the writes that add this photo to the
 * index and record the flag (call it after the transaction's other reads).
 */
export async function findDuplicates(
  tx: Transaction,
  db: Firestore,
  photo: { hash: string; listingId: string; mediaId: string },
  now: Date,
): Promise<{ matches: PhotoMatch[]; write: () => void }> {
  if (tooPlain(photo.hash)) return { matches: [], write: () => {} };
  const refs = bandRefs(db, photo.hash);
  const snaps = await tx.getAll(...refs);
  const best = new Map<string, PhotoMatch>();
  for (const s of snaps) {
    for (const e of (s.get('entries') ?? []) as Entry[]) {
      if (e.l === photo.listingId) continue;
      const bits = hammingDistance(photo.hash, e.h);
      const key = `${e.l}/${e.m}`;
      if (bits <= SAME_PHOTO_BITS && (best.get(key)?.bits ?? 99) > bits) best.set(key, { listingId: e.l, mediaId: e.m, bits });
    }
  }
  const matches = [...best.values()].sort((a, b) => a.bits - b.bits).slice(0, 5);
  return {
    matches,
    write: () => {
      const entry: Entry = { h: photo.hash, l: photo.listingId, m: photo.mediaId };
      for (const ref of refs) tx.set(ref, { entries: FieldValue.arrayUnion(entry) }, { merge: true });
      if (matches.length) {
        tx.set(db.collection('photoFlags').doc(`${photo.listingId}_${photo.mediaId}`), {
          listingId: photo.listingId,
          mediaId: photo.mediaId,
          matches,
          at: now,
        });
      }
    },
  };
}
