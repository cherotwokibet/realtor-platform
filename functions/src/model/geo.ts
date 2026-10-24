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
