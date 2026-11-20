/** Geohash (base32, as used by geofire) and URL slugs. Pure functions. */

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/** Standard geohash; 9 chars is about 5 m, enough for a listing pin. */
export function geohash(lat: number, lng: number, precision = 9): string {
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) throw new RangeError(`bad coordinates ${lat},${lng}`);
  let latLo = -90, latHi = 90, lngLo = -180, lngHi = 180;
  let hash = '', bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    if (even) {
      const mid = (lngLo + lngHi) / 2;
      if (lng >= mid) { ch = (ch << 1) | 1; lngLo = mid; } else { ch <<= 1; lngHi = mid; }
    } else {
      const mid = (latLo + latHi) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latLo = mid; } else { ch <<= 1; latHi = mid; }
    }
    even = !even;
    if (++bit === 5) { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

/** True when the point is inside the closed outline (ray casting). */
export function insidePolygon(lat: number, lng: number, poly: ReadonlyArray<{ lat: number; lng: number }>): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i], b = poly[j];
    if (a.lat > lat !== b.lat > lat && lng < ((b.lng - a.lng) * (lat - a.lat)) / (b.lat - a.lat) + a.lng) inside = !inside;
  }
  return inside;
}

/** True when two of the outline's edges cross (a figure-eight is no area). */
export function selfIntersects(c: ReadonlyArray<{ lat: number; lng: number }>): boolean {
  const n = c.length;
  if (n < 4) return false;
  const cross = (o: { lat: number; lng: number }, a: { lat: number; lng: number }, b: { lat: number; lng: number }) =>
    (a.lng - o.lng) * (b.lat - o.lat) - (a.lat - o.lat) * (b.lng - o.lng);
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (j === i + 1 || (i === 0 && j === n - 1)) continue;
      const [p1, p2, q1, q2] = [c[i], c[(i + 1) % n], c[j], c[(j + 1) % n]];
      const d1 = cross(q1, q2, p1), d2 = cross(q1, q2, p2), d3 = cross(p1, p2, q1), d4 = cross(p1, p2, q2);
      if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) return true;
    }
  }
  return false;
}

/** "2 Bedroom Apartment, Kilimani!" -> "2-bedroom-apartment-kilimani". */
export function slugify(text: string): string {
  return text
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80)
    .replace(/-+$/, '');
}
